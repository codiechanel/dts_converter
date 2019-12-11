import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:dts_converter/dts_converter.dart';

const String DEFAULT_TARGET_LIBRARY = "";
const String DEFAULT_SOURCE_LIBRARY = "";
const String DEFAULT_SOURCE_DIR = "";
const String DEFAULT_TARGET_DIR = "lib";
const bool FULL_DART_PROJECT = false;

Converter _converter = new Converter();

String dart_library_name;
String source_library_name;
String source_basedir;
String target_basedir;
bool create_full_project;

String library_file_content;
String dart_file_content;

void main(List args) {
  _setupArgs(args);

  if (source_basedir == DEFAULT_SOURCE_DIR) {
    print("Well, at least provide the --source dir, will you?");
    exit(1);
  }

  if (target_basedir == new File(target_basedir).absolute.path) {
    print(
        "Please provide a --target path relative to your working directory (the directory you're running this script from).");
    exit(1);
  }

  if (source_library_name == DEFAULT_SOURCE_LIBRARY) {
    print(
        "Please provide a --source-library name equivalent to what you find under 'declare var' in the d.ts source file, for example 'Chart' or 'THREE'.");
    exit(1);
  }

  if (dart_library_name == DEFAULT_TARGET_LIBRARY) {
    dart_library_name = source_library_name;
  }

  //prepare the library file so we can append 'part' files
  library_file_content = '''
@JS('$source_library_name')
library $dart_library_name;

import "package:func/func.dart";
import "package:js/js.dart";
import 'dart:html';
import 'dart:web_audio' show AudioContext;
import 'dart:typed_data';

''';

  //prepare the dart file so we can append the converted things
  if (create_full_project) {
    dart_file_content = '''
part of $dart_library_name;


''';
  } else {
    dart_file_content = library_file_content;
  }

  /* iterate over source path, grab *.ts files */
  Directory sourceDir = new Directory(join(source_basedir));
  if (sourceDir.existsSync()) {
    sourceDir
        .listSync(recursive: true, followLinks: false)
        .forEach((FileSystemEntity entity) {
      if (FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.FILE &&
          extension(entity.path).toLowerCase() == ".ts") {
        _convert(entity.path);
      }
    });
    if (create_full_project) {
      _writeTemplates();
    } else {
      _addLibraryToRootPubspec();
    }
  } else {
    print(
        "The directory that was provided as source_basedir does not exist: $source_basedir");
    exit(1);
  }
}

/// Writes pubspec.yaml and package.dart into the newly created package.
void _writeTemplates() {
  //create library file
  new File(join(target_basedir, "lib", "$dart_library_name.dart")).absolute
    ..createSync(recursive: true)
    ..writeAsStringSync(library_file_content);

  //create pubspec .yaml file
  String pubspecFileContent = '''
name: $dart_library_name
version: 0.1.0
description: autogenerated dart js interop type definition for $source_library_name
dependencies:
  logging: any
  func: ^0.1.0
  js: ^0.6.0
  args: any
  path: any
''';

  new File(join(target_basedir, "pubspec.yaml")).absolute
    ..createSync(recursive: true)
    ..writeAsStringSync(pubspecFileContent);
}

/// Adds the newly created package as dependency to the project's root pubspec.yaml.
void _addLibraryToRootPubspec() {
  String insertionString = '''
dependencies:
  $dart_library_name:
    path: ${join(target_basedir, dart_library_name)}''';

  File pubspecRootFile = new File('pubspec.yaml').absolute;
  String pubspecRootFileContent = pubspecRootFile.readAsStringSync();
  if (!pubspecRootFileContent.contains(dart_library_name)) {
    pubspecRootFileContent = pubspecRootFileContent
        .split(new RegExp("dependencies\\s*:"))
        .join(insertionString);
    pubspecRootFile.writeAsStringSync(pubspecRootFileContent,
        mode: FileMode.WRITE);
  }
}

/// Takes a File path, e.g. test/chart/chart.d.ts, and writes it to
/// the output directory provided, e.g. lib/src/chart.beta.d.dart.
/// During the process, excessive RegExp magic is applied.
void _convert(String asFilePath) {
  //e.g. test/chart/chart.d.ts
  //print("asFilePath: $asFilePath");

  File asFile = new File(asFilePath);

  //Package name, e.g. chart/foo
  String dartFilePath =
      asFilePath.replaceFirst(new RegExp(source_basedir + "/"), "");
  dartFilePath = dirname(dartFilePath);
  //print("dartFilePath: $dartFilePath");

  //New filename, e.g. chart.beta.d.dart
  String dartFileName = basenameWithoutExtension(asFile.path)
      .replaceAllMapped(new RegExp("(IO|I|[^A-Z-])([A-Z])"),
          (Match m) => (m.group(1) + "_" + m.group(2)))
      .toLowerCase();
  dartFileName += ".dart";
  //print("dartFileName: $dartFileName");

  String asFileContents = asFile.readAsStringSync();
  String dartFileContents = _applyMagic(asFileContents);

  //Write new file
  String dartFileNameFull = join(
      target_basedir,
      create_full_project ? "lib" : "",
      create_full_project ? "src" : "",
      dart_library_name.toLowerCase(),
      dartFileName);
  //print("dartFileNameFull: $dartFileNameFull");
  new File(dartFileNameFull).absolute
    ..createSync(recursive: true)
    ..writeAsStringSync(dartFileContents);

  library_file_content +=
      "\npart 'src/${dart_library_name.toLowerCase()}/$dartFileName';";

  // format code in Dart style
  if (Platform.isWindows) {
    Process.runSync("dartfmt.bat", ['-w', dartFileNameFull]);
  } else {
    Process.runSync("dartfmt", ['-w', dartFileNameFull]);
  }
}

/// Applies magic to an .d.ts file String, converting it to almost error free Dart.
/// Please report errors and edge cases to github issue tracker.
String _applyMagic(String f) {
  return _converter.convert(f, source_library_name, dart_file_content);
}

/// Manages the script's arguments and provides instructions and defaults for the --help option.
void _setupArgs(Iterable args) {
  ArgParser argParser = new ArgParser();
  argParser.addOption('target-library',
      defaultsTo: DEFAULT_TARGET_LIBRARY,
      help: 'The name of the library to be generated.',
      valueHelp: 'target-library', callback: (_dlibrary) {
    dart_library_name = _dlibrary;
  });
  argParser.addOption('source-library',
      defaultsTo: DEFAULT_SOURCE_LIBRARY,
      help: 'The name of the javascript library to convert.',
      valueHelp: 'source-library', callback: (_slibrary) {
    source_library_name = _slibrary;
  });
  argParser.addOption('source',
      abbr: 's',
      defaultsTo: DEFAULT_SOURCE_DIR,
      help:
          'The path (relative or absolute) to the Typescript .d.ts source file(s) to convert.',
      valueHelp: 'source', callback: (_source_basedir) {
    source_basedir = _source_basedir;
  });
  argParser.addOption('target',
      abbr: 't',
      defaultsTo: DEFAULT_TARGET_DIR,
      help:
          'The path (relative!) the generated Dart library will be written to. Usually, your Dart project\'s \'lib\' directory.',
      valueHelp: 'target', callback: (_target_basedir) {
    target_basedir = _target_basedir;
  });
  argParser.addFlag('create-project',
      abbr: 'c',
      negatable: false,
      defaultsTo: FULL_DART_PROJECT,
      help: 'Create full dart project with pubspec and library file.',
      callback: (_flibrary) {
    create_full_project = _flibrary;
  });

  argParser.addFlag('help', negatable: false, help: 'Displays the help.',
      callback: (help) {
    if (help) {
      print(argParser.usage);
      exit(1);
    }
  });

  argParser.parse(args);
}