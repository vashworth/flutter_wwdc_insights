import 'dart:io';
import 'package:console_bars/console_bars.dart';
import 'package:flutter_wwdc_insights/flutter_wwdc_insights.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:args/args.dart';

void main(List<String> arguments) async {
  final argParser = ArgParser()
    ..addOption(
      'url',
      abbr: 'u',
      help: 'The WWDC video URL to fetch insights for.',
    )
    ..addOption(
      'url-list',
      abbr: 'l',
      help:
          'A WWDC URL listing multiple sessions (e.g., https://developer.apple.com/videos/wwdc2025/).',
    )
    ..addOption(
      'flutter-path',
      abbr: 'f',
      help:
          'Path to the Flutter repository. Fallback is the FLUTTER_ROOT environment variable.',
    )
    ..addFlag(
      'gemini-cli',
      help: 'Use gemini CLI instead of Genkit.',
      defaultsTo: false,
    )
    ..addOption(
      'model',
      abbr: 'm',
      help: 'Gemini model to use.',
      allowed: ['auto', 'gemini-flash-latest', 'gemini-pro-latest'],
      defaultsTo: 'gemini-flash-latest',
      valueHelp: 'auto is only available for Gemini CLI',
    )
    ..addFlag(
      'reccommended-actions',
      abbr: 'r',
      help: 'Generate a list of actions recommended based on the session.',
      defaultsTo: true,
    )
    ..addOption(
      'output',
      abbr: 'o',
      help:
          'Output directory where the parsed results and AI analysis will be saved.',
    )
    ..addFlag(
      'parse-only',
      help: 'Only parse the session HTML and skip AI analysis.',
      defaultsTo: false,
    );

  ArgResults results;
  String? url;
  String? urlList;
  try {
    results = argParser.parse(arguments);
    url = results['url'] as String?;
    urlList = results['url-list'] as String?;
    if ((url == null || url.isEmpty) && (urlList == null || urlList.isEmpty)) {
      throw FormatException('Option url is mandatory.');
    }
  } catch (e) {
    print('Error parsing arguments: $e');
    print('Usage: dart bin/flutter_wwdc_insights.dart -u <url> [options]');
    print(argParser.usage);
    exit(1);
  }

  final cacheDirectory = 'html_cache';
  final parser = WwdcParser(cacheDirectory: cacheDirectory);
  print('HTML cache directory: $cacheDirectory\n');

  final useGeminiCli = results['gemini-cli'] == true;
  String model = results['model'] as String;
  final includeRecommendedActions = results['reccommended-actions'] == true;
  final customOutput = results['output'] as String?;
  final parseOnly = results['parse-only'] == true;

  final flutterPath = _resolveFlutterPath(results);
  if (useGeminiCli && (flutterPath == null || flutterPath.isEmpty)) {
    print('Error: Flutter directory is required when using --gemini-cli.');
    exit(1);
  }
  if (model == 'auto' && !useGeminiCli) {
    print('Error: auto model is only available for Gemini CLI.');
    exit(1);
  }
  if (useGeminiCli) {
    if (model == 'gemini-flash-latest') {
      model = 'gemini-3-flash-preview';
    } else if (model == 'gemini-pro-latest') {
      model = 'gemini-3.1-pro-preview';
    }
  }
  final method = useGeminiCli ? 'gemini-cli' : 'genkit';
  final actionsSuffix = includeRecommendedActions ? '/actions' : '';
  final outputDirectory = customOutput ??
      (parseOnly ? 'output/parsed' : 'output/$method/$model$actionsSuffix');
  print('Output directory: $outputDirectory\n');

  List<String> sessionUrls = [];
  if (urlList != null && urlList.isNotEmpty) {
    print('Fetching sessions list from: $urlList\n');
    sessionUrls = await parser.parseSessionUrls(urlList);
    print('Found ${sessionUrls.length} sessions to process.\n');
  } else if (url != null && url.isNotEmpty) {
    sessionUrls = [url];
  }
  try {
    if (parseOnly) {
      print('Parsing sessions...');
    } else if (useGeminiCli) {
      print('Running AI analysis via Gemini CLI...');
    } else {
      print('Running AI analysis via Genkit and Gemini...');
    }
    final stopWatch = Stopwatch();
    stopWatch.start();
    FillingBar? statusBar;
    if (stdout.hasTerminal) {
      try {
        statusBar = FillingBar(desc: 'Processing', total: sessionUrls.length);
      } catch (_) {}
    }
    for (final sessionUrl in sessionUrls) {
      await _processSessionUrl(
        url: sessionUrl,
        parser: parser,
        flutterPath: flutterPath,
        cacheDirectory: cacheDirectory,
        outputDirectory: outputDirectory,
        includeRecommendedActions: includeRecommendedActions,
        useGeminiCli: useGeminiCli,
        model: model,
        parseOnly: parseOnly,
      );
      statusBar?.increment();
    }
    stopWatch.stop();
    print('Done!');
    print(
      'Processing ${sessionUrls.length} sessions took ${stopWatch.elapsedMilliseconds / 1000} seconds.',
    );
    if (parseOnly && (urlList == null || urlList.isEmpty) && url != null && url.isNotEmpty) {
      final mdFile = _getMarkdownOutputFile(
        outputDirectory,
        url,
        includeRecommendedActions: includeRecommendedActions,
      );
      if (mdFile.existsSync()) {
        print('Parsed session: ${mdFile.absolute.path}');
      }
    }
  } catch (e, stackTrace) {
    print('An error occurred while parsing the sessions list: $e');
    print(stackTrace);
  }
}

Future<void> _processSessionUrl({
  required String url,
  required WwdcParser parser,
  required String? flutterPath,
  required String cacheDirectory,
  required String outputDirectory,
  required bool includeRecommendedActions,
  required bool useGeminiCli,
  required String model,
  required bool parseOnly,
}) async {
  final mdFile = _getMarkdownOutputFile(
    outputDirectory,
    url,
    includeRecommendedActions: includeRecommendedActions,
  );
  if (await mdFile.exists()) {
    return;
  }

  try {
    final insights = await parser.parseUrl(url);

    if (insights.transcript.isEmpty) {
      print('\n[Skipped] No transcript for: $url');
      return;
    }

    // Basic markdown generation
    var mdContent = insights.toMarkdown();

    // Check for API key or gemini-cli to perform AI analysis
    final (updatedMdContent, aiAnalysis) = parseOnly
        ? (mdContent, null)
        : await _runAiRelevanceAnalysis(
            flutterPath: flutterPath,
            mdContent: mdContent,
            includeRecommendedActions: includeRecommendedActions,
            useGeminiCli: useGeminiCli,
            model: model,
          );
    mdContent = updatedMdContent;

    // If AI analysis is present, append it to a file in the output directory called "ai_insights.md"
    if (aiAnalysis != null && aiAnalysis.isNotEmpty) {
      final aiInsightsFile = File('$outputDirectory/ai_insights.md');
      aiInsightsFile.createSync(recursive: true);
      // Append the session title and the AI analysis
      final appendContent =
          '''

## ${insights.title}
URL: $url

$aiAnalysis

''';
      aiInsightsFile.writeAsStringSync(appendContent, mode: FileMode.append);
    }

    // Save parsed output (plus optional AI analysis) to markdown file
    await _saveMarkdownOutput(mdFile, mdContent);
  } catch (e, stackTrace) {
    print('An error occurred while parsing the URL $url: $e');
    print(stackTrace);
  }
}

String? _resolveFlutterPath(ArgResults results) {
  var flutterPath = results['flutter-path'] as String?;
  var isFromEnv = false;
  if (flutterPath == null || flutterPath.isEmpty) {
    final envPath = Platform.environment['FLUTTER_ROOT'];
    if (envPath != null && envPath.isNotEmpty) {
      flutterPath = envPath;
      isFromEnv = true;
    }
  }
  if (flutterPath != null) {
    if (isFromEnv) {
      print('Using Flutter repository path from FLUTTER_ROOT: $flutterPath');
    } else {
      print('Using Flutter repository path: $flutterPath');
    }
  }
  return flutterPath;
}

File _getMarkdownOutputFile(
  String outputDirectory,
  String url, {
  bool includeRecommendedActions = false,
}) {
  final cacheFileName = url
      .replaceAll(RegExp(r'https?://'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return File('$outputDirectory/$cacheFileName.md');
}

Future<File> _saveMarkdownOutput(File mdFile, String mdContent) async {
  final parentDir = mdFile.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }
  await mdFile.writeAsString(mdContent);
  return mdFile;
}

Future<(String, String?)> _runAiRelevanceAnalysis({
  required String? flutterPath,
  required String mdContent,
  required bool includeRecommendedActions,
  required bool useGeminiCli,
  required String model,
}) async {
  final apiKey = Platform.environment['WWDC_GEMINI_API_KEY'];
  String? aiAnalysis;

  if (useGeminiCli) {
    if (flutterPath == null || flutterPath.isEmpty) {
      print('Error: Flutter directory is required when using --gemini-cli.');
      exit(1);
    }
    try {
      aiAnalysis = await _runGeminiCliAnalysis(
        flutterPath,
        mdContent,
        includeRecommendedActions: includeRecommendedActions,
        model: model,
      );
      return (
        '$mdContent\n## AI Relevance & Importance Analysis\n\n$aiAnalysis\n',
        aiAnalysis,
      );
    } catch (e) {
      print('Warning: AI analysis failed: $e\n');
    }
  } else if (apiKey != null && apiKey.isNotEmpty) {
    try {
      aiAnalysis = await _runAiAnalysis(
        apiKey,
        mdContent,
        includeRecommendedActions: includeRecommendedActions,
        model: model,
      );
      return (
        '$mdContent\n## AI Relevance & Importance Analysis\n\n$aiAnalysis\n',
        aiAnalysis,
      );
    } catch (e) {
      print('Warning: AI analysis failed: $e\n');
    }
  } else {
    print(
      'Notice: No GEMINI_API_KEY found in environment or temp/txt. Skipping AI analysis.\n',
    );
  }

  return (mdContent, null);
}

String _buildPrompt(String content, {bool includeRecommendedActions = false}) {
  String recommendActionsPrompt = '';
  String recommendedActionsResponse = '';
  if (includeRecommendedActions) {
    recommendActionsPrompt =
        '3. What actions should each Flutter team take as a result of this session? '
        'Only include teams under "Recommended actions" that have High relevance.';
    recommendedActionsResponse = '''
##### 3. Recommended actions
* **<Team Name>**: <insert action here>
''';
  }

  final prompt =
      '''
<system_instruction>
You are an expert mobile developer with deep knowledge of both native iOS development (Apple frameworks) and the Flutter cross-platform framework.
</system_instruction>

<session_content>
$content
</session_content>

<context>
Flutter Teams:
* Core Framework: design language and features, etc.
* Text Input: Text editing, First Responder, text entry, languages, text predictions, dictation, text field, text view, keyboard, fonts, SF Symbols, Pencil, scribble, etc.
* Accessibility: accessibility, semantics, VoiceOver, screenreader, Voice Control, Assistive Keyboard, Nutrition labels, etc.
* Ecosystem & Plugins: plugins, platform APIs, etc. Only rank High if relevant to Flutter's 1P plugins (camera, cross_file, file_selector, google_maps_flutter, google_sign_in, image_picker, in_app_purchase, local_auth, path_provider, pointer_interceptor, quick_actions, shared_preferences, url_launcher, video_player, webview_flutter).
* Platform Integration: App Intents, Live Activities, App extensions, Widgets, etc
* Engine: UIKit, graphics, rendering, animation, responder chain, touch gestures, Metal, Impeller, Skia, Vulkan, WebGL, Objective-C, Swift 6, language interop, SwiftUI (Flutter can use SwiftUI APIs), etc
* Tooling & Developer Experience: App Store submissions, Xcode, Swift Package Manager, build systems, command line tools, debugging, language interop, etc
* Web: Safari, WebKit, etc.
* Infra: testing, automation, certificates, provisioning, security, simulators, toolchains, command line tools, etc
* Security & Privacy: privacy, security, etc
* Other: For any topics that don't fall under the other teams but have relevance to Flutter
</context>

<task>
Based on the session content provided above, analyze the material and provide a short, concise summary and analysis answering:
1. Using a rank of Low, Medium, or High, rate the importance of this session to Flutter contributors (users who build the Flutter framework and CLI) overall.
   * **High:** The session covers mandatory requirements, breaking changes, architectural changes, deprecations, massive ecosystem shifts, disruptions to existing workflows, breaking toolchain changes.
   * **Medium:** The session covers new iOS/macOS features or capabilities, but it isn't strictly breaking or manditory.
   * **Low:** The session covers new iOS/macOS features or APIs that could be provided through a Flutter plugin, or is focused on a platform Flutter does not support (visionOS, watchOS).
2. Using a rank of Low, Medium, or High, rate the relevance of this session to Flutter per team below.
$recommendActionsPrompt

<response_format>
Provide your response in markdown format exactly matching the structure below.
Only list teams under "Relevance to Flutter" that are ranked Medium or High.

**Summary:** <insert summary of topic and why it is or isn't important/relevant to Flutter in 1-4 sentences>

##### 1. Overall Importance to Flutter Contributors

**<insert rank here>**: <insert justification for rank in 1-3 sentences>

##### 2. Relevance to Flutter Contributor Teams

* **<Team Name>** (<insert rank here>): <insert 1 sentence justification>

$recommendedActionsResponse
</response_format>
''';

  return prompt;
}

Future<String> _runAiAnalysis(
  String apiKey,
  String content, {
  bool includeRecommendedActions = false,
  required String model,
}) async {
  final ai = Genkit(plugins: [googleAI(apiKey: apiKey)]);
  final prompt = _buildPrompt(
    content,
    includeRecommendedActions: includeRecommendedActions,
  );

  final response = await ai.generate(
    model: googleAI.gemini(model),
    prompt: prompt,
  );
  return response.text;
}

Future<String> _runGeminiCliAnalysis(
  String flutterPath,
  String content, {
  bool includeRecommendedActions = false,
  required String model,
}) async {
  final prompt = _buildPrompt(
    content,
    includeRecommendedActions: includeRecommendedActions,
  );

  final result = await Process.run('/usr/local/bin/gemini', [
    '--prompt',
    prompt,
    '--skip-trust',
    '--model',
    model,
  ], workingDirectory: flutterPath);

  if (result.exitCode != 0) {
    throw ProcessException(
      '/usr/local/bin/gemini',
      ['--prompt', prompt, '--skip-trust'],
      'Process exited with code ${result.exitCode}\nStdout: ${result.stdout}\nStderr: ${result.stderr}',
      result.exitCode,
    );
  }

  return result.stdout as String;
}
