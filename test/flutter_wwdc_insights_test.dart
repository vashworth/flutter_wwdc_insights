import 'dart:io';
import 'package:flutter_wwdc_insights/flutter_wwdc_insights.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:args/args.dart';

void main() {
  group('WwdcParser Tests', () {
    const mockHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Customize your app for Assistive Access - WWDC25 - Videos - Apple Developer</title>
</head>
<body>
  <li class="supplement details " data-supplement-id="details">
    <h1>Mock WWDC Video</h1>
    <p>Mock About Description</p>

    <h2>Chapters</h2>
    <ul class="no-bullet chapter-list">
      <li class="chapter-item" data-start-time="0" data-chapter-end-time="60" data-chapter-lenght="60" data-chapter-index="1">
        <a href="?time=0">Introduction</a>
      </li>
    </ul>

    <h2>Resources</h2>
    <ul class="links small">
      <li class="document"><a href="https://example.com/doc">MockDoc</a></li>
      <li class="download">
        <ul class="options">
          <li><a href="https://example.com/video.mp4">HD Video</a></li>
        </ul>
      </li>
    </ul>

    <h2>Related Videos</h2>
    <h4>WWDC25</h4>
    <ul class="links small">
      <li class="video"><a href="/videos/play/wwdc2025/123">Another Swift Video</a></li>
    </ul>
  </li>

  <li class="supplement summary margin-top-small" data-supplement-id="summary">
    <ul class="no-bullet">
      <li>0:00 - <a class="jump-to-time" href="?time=0" data-start-time="0">Introduction</a></li>
      <li class="chapter-summary"><p>This is the chapter summary text.</p></li>
    </ul>
  </li>

  <section id="transcript-content">
    <p>
      <span class="sentence"><span data-start="0.0">Hello and welcome.</span></span>
      <span class="sentence"><span data-start="2.5">Let's learn Dart!</span></span>
    </p>
  </section>

  <li class="supplement sample-code" data-supplement-id="sample-code">
    <section>
      <ul class="no-bullet">
        <li class="sample-code-main-container">
          <p>0:00 - <a class="jump-to-time-sample" href="?time=0" data-start-time="0">Sample Code Description</a></p>
          <pre class="code-source"><code>void main() {}</code></pre>
        </li>
      </ul>
    </section>
  </li>
</body>
</html>
''';

    test('Parses all sections correctly from mock HTML', () {
      final parser = WwdcParser();
      final insights = parser.parseHtml(mockHtml, url: 'https://example.com');

      // Test Title and Description
      expect(insights.title, equals('Mock WWDC Video'));
      expect(insights.aboutDescription, equals('Mock About Description'));

      // Test Chapters
      expect(insights.chapters.length, equals(1));
      final firstChapter = insights.chapters[0];
      expect(firstChapter.index, equals(1));
      expect(firstChapter.title, equals('Introduction'));
      expect(firstChapter.startTime, equals(0));
      expect(firstChapter.endTime, equals(60));
      expect(firstChapter.length, equals(60));

      // Test Resources
      expect(insights.resources.length, equals(2));
      expect(insights.resources[0].title, equals('MockDoc'));
      expect(insights.resources[0].url, equals('https://example.com/doc'));
      expect(insights.resources[0].type, equals('document'));
      expect(insights.resources[1].title, equals('HD Video'));
      expect(insights.resources[1].url, equals('https://example.com/video.mp4'));
      expect(insights.resources[1].type, equals('download'));

      // Test Related Videos
      expect(insights.relatedVideos.length, equals(1));
      expect(insights.relatedVideos[0].title, equals('Another Swift Video'));
      expect(insights.relatedVideos[0].url, equals('https://developer.apple.com/videos/play/wwdc2025/123'));
      expect(insights.relatedVideos[0].collection, equals('WWDC25'));

      // Test Summaries
      expect(insights.summary.length, equals(1));
      expect(insights.summary[0].chapterTitle, equals('Introduction'));
      expect(insights.summary[0].startTime, equals(0));
      expect(insights.summary[0].content, equals('This is the chapter summary text.'));

      // Test Transcript
      expect(insights.transcript.length, equals(1));
      expect(insights.transcript[0].sentences.length, equals(2));
      expect(insights.transcript[0].sentences[0], equals('Hello and welcome.'));
      expect(insights.transcript[0].sentences[1], equals("Let's learn Dart!"));

      // Test Code Snippets
      expect(insights.codeSnippets.length, equals(1));
      expect(insights.codeSnippets[0].description, equals('Sample Code Description'));
      expect(insights.codeSnippets[0].startTime, equals(0));
      expect(insights.codeSnippets[0].code, equals('void main() {}'));
    });

    test('Caches fetched HTML and loads it from cache on subsequent calls', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_parser_test_cache');
      var callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(mockHtml, 200);
      });

      final parser = WwdcParser(
        cacheDirectory: tempDir.path,
        httpClient: mockClient,
      );

      const testUrl = 'https://developer.apple.com/videos/play/wwdc2025/238/';

      // First parse: should fetch from client and write to cache
      final insights1 = await parser.parseUrl(testUrl);
      expect(insights1.title, equals('Mock WWDC Video'));
      expect(callCount, equals(1));

      // Verify cache file exists
      final expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${tempDir.path}/$expectedFileName');
      expect(await cacheFile.exists(), isTrue);

      // Second parse: should load from cache without calling mockClient again
      final insights2 = await parser.parseUrl(testUrl);
      expect(insights2.title, equals('Mock WWDC Video'));
      expect(callCount, equals(1)); // Should still be 1 since it used cache

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('Does not cache if cacheDirectory is null', () async {
      var callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(mockHtml, 200);
      });

      final parser = WwdcParser(
        cacheDirectory: null,
        httpClient: mockClient,
      );

      const testUrl = 'https://developer.apple.com/videos/play/wwdc2025/238/';

      // First parse: should fetch from client
      await parser.parseUrl(testUrl);
      expect(callCount, equals(1));

      // Second parse: should fetch from client again since cache is disabled
      await parser.parseUrl(testUrl);
      expect(callCount, equals(2));
    });

    test('Generates correct cacheFileName and Markdown content', () {
      final parser = WwdcParser();
      final insights = parser.parseHtml(mockHtml, url: 'https://developer.apple.com/videos/play/wwdc2025/238/');

      expect(insights.cacheFileName, equals('developer_apple_com_videos_play_wwdc2025_238'));

      final markdown = insights.toMarkdown();
      expect(markdown, contains('# Mock WWDC Video'));
      expect(markdown, contains('Source URL: [https://developer.apple.com/videos/play/wwdc2025/238/](https://developer.apple.com/videos/play/wwdc2025/238/)'));
      expect(markdown, contains('## About\nMock About Description'));
      expect(markdown, contains('- Chapter 1: Introduction (0s - 60s)'));
      expect(markdown, contains('## Resources\n- [MockDoc](https://example.com/doc) [document]'));
      expect(markdown, contains('## Related Videos\n- **WWDC25** - [Another Swift Video](https://developer.apple.com/videos/play/wwdc2025/123)'));
      expect(markdown, contains('### Introduction (starts at 0s)\nThis is the chapter summary text.'));
      expect(markdown, contains('### Sample Code Description (starts at 0s)\n```swift\nvoid main() {}\n```'));
      expect(markdown, contains('## Transcript\nHello and welcome. Let\'s learn Dart!'));
    });

    test('parseSessionUrls extracts and resolves all session links', () async {
      const mockListingHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="videos-grid">
    <a href="/videos/play/wwdc2025/101/" class="vc-card">Session 101</a>
    <a href="/videos/play/wwdc2025/102/" class="vc-card">Session 102</a>
    <a href="https://developer.apple.com/videos/play/wwdc2025/103/" class="vc-card">Session 103</a>
    <a href="/other-path/" class="vc-card">Non-session link</a>
  </div>
</body>
</html>
''';

      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(mockListingHtml, 200);
      });

      final parser = WwdcParser(cacheDirectory: null, httpClient: mockClient);
      final urls = await parser.parseSessionUrls('https://developer.apple.com/videos/wwdc2025/');

      expect(callCount, equals(1));
      expect(urls, unorderedEquals([
        'https://developer.apple.com/videos/play/wwdc2025/101/',
        'https://developer.apple.com/videos/play/wwdc2025/102/',
        'https://developer.apple.com/videos/play/wwdc2025/103/',
      ]));
    });

    test('parseSessionUrls caches fetched HTML and loads it from cache on subsequent calls', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_parser_test_cache_listing');
      var callCount = 0;

      const mockListingHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="videos-grid">
    <a href="/videos/play/wwdc2025/101/" class="vc-card">Session 101</a>
  </div>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(mockListingHtml, 200);
      });

      final parser = WwdcParser(
        cacheDirectory: tempDir.path,
        httpClient: mockClient,
      );

      const testUrl = 'https://developer.apple.com/videos/wwdc2025/';

      // First parse: should fetch from client and write to cache
      final urls1 = await parser.parseSessionUrls(testUrl);
      expect(urls1.length, equals(1));
      expect(callCount, equals(1));

      // Verify cache file exists
      final expectedFileName = 'developer_apple_com_videos_wwdc2025.html';
      final cacheFile = File('${tempDir.path}/$expectedFileName');
      expect(await cacheFile.exists(), isTrue);

      // Second parse: should load from cache without calling mockClient again
      final urls2 = await parser.parseSessionUrls(testUrl);
      expect(urls2.length, equals(1));
      expect(callCount, equals(1)); // Should still be 1 since it used cache

      // Clean up
      tempDir.deleteSync(recursive: true);
    });
  });

  group('CLI Integration Tests', () {
    test('CLI exits with error when URL is missing', () async {
      final result = await Process.run(
        Platform.executable,
        [
          'bin/flutter_wwdc_insights.dart',
        ],
      );

      expect(result.exitCode, equals(1));
      expect(result.stdout, contains('Option url is mandatory.'));
      expect(result.stdout, contains('Usage: dart bin/flutter_wwdc_insights.dart -u <url> [options]'));
    });

    test('CLI parses --flutter-path and uses it', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_cli_test');
      final dotCacheDir = Directory('${tempDir.path}/html_cache');
      await dotCacheDir.create(recursive: true);

      const expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${dotCacheDir.path}/$expectedFileName');

      // Write the mock HTML to the cache file so the CLI reads it instead of hitting the network
      await cacheFile.writeAsString('''
<!DOCTYPE html>
<html>
<head>
  <title>Mock Title</title>
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video from CLI Cache</h1>
    <p>Mock description text</p>
  </li>
  <section id="transcript-content">
    <p>
      <span class="sentence">This is a mock transcript sentence to prevent skipping.</span>
    </p>
  </section>
</body>
</html>
''');

      final scriptPath = p.absolute('bin/flutter_wwdc_insights.dart');

      // Run the CLI using Process.run
      final result = await Process.run(
        Platform.executable,
        [
          scriptPath,
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
          '--flutter-path',
          tempDir.path,
        ],
        environment: {
          'WWDC_GEMINI_API_KEY': '',
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Using Flutter repository path: ${tempDir.path}'));
      expect(result.stdout, contains('HTML cache directory: html_cache'));
      expect(result.stdout, contains('Notice: No GEMINI_API_KEY found in environment or temp/txt. Skipping AI analysis.'));

      tempDir.deleteSync(recursive: true);
    });

    test('CLI falls back to FLUTTER_ROOT environment variable if --flutter-path is omitted', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_cli_env_test');
      final dotCacheDir = Directory('${tempDir.path}/html_cache');
      await dotCacheDir.create(recursive: true);

      const expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${dotCacheDir.path}/$expectedFileName');

      // Write the mock HTML to the cache file so the CLI reads it instead of hitting the network
      await cacheFile.writeAsString('''
<!DOCTYPE html>
<html>
<head>
  <title>Mock Title</title>
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video from CLI Env Cache</h1>
    <p>Mock description text</p>
  </li>
  <section id="transcript-content">
    <p>
      <span class="sentence">This is a mock transcript sentence to prevent skipping.</span>
    </p>
  </section>
</body>
</html>
''');

      final scriptPath = p.absolute('bin/flutter_wwdc_insights.dart');

      // Run the CLI using Process.run with FLUTTER_ROOT environment variable set
      final result = await Process.run(
        Platform.executable,
        [
          scriptPath,
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
        ],
        environment: {
          'FLUTTER_ROOT': tempDir.path,
          'WWDC_GEMINI_API_KEY': '',
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Using Flutter repository path from FLUTTER_ROOT: ${tempDir.path}'));
      expect(result.stdout, contains('HTML cache directory: html_cache'));
      expect(result.stdout, contains('Notice: No GEMINI_API_KEY found in environment or temp/txt. Skipping AI analysis.'));

      tempDir.deleteSync(recursive: true);
    });

    test('CLI with --gemini-cli but no flutter-path/FLUTTER_ROOT exits with error', () async {
      final result = await Process.run(
        Platform.executable,
        [
          'bin/flutter_wwdc_insights.dart',
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
          '--gemini-cli',
        ],
        environment: {
          'FLUTTER_ROOT': '',
        },
      );

      expect(result.exitCode, isNot(equals(0)));
      expect(result.stdout, contains('Error: Flutter directory is required when using --gemini-cli.'));
    });

    test('CLI parses --gemini-cli flag correctly', () {
      final argParser = ArgParser()
        ..addOption(
          'url',
          abbr: 'u',
        )
        ..addOption(
          'url-list',
          abbr: 'l',
        )
        ..addOption(
          'flutter-path',
          abbr: 'f',
        )
        ..addFlag(
          'gemini-cli',
          defaultsTo: false,
        );

      final results = argParser.parse([
        '--url',
        'https://developer.apple.com/videos/play/wwdc2025/238/',
        '--flutter-path',
        '/path/to/flutter',
        '--gemini-cli',
      ]);

      expect(results['url'], equals('https://developer.apple.com/videos/play/wwdc2025/238/'));
      expect(results['flutter-path'], equals('/path/to/flutter'));
      expect(results['gemini-cli'], isTrue);
    });

    test('CLI uses custom output directory when --output is provided', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_cli_output_test');
      final dotCacheDir = Directory('${tempDir.path}/html_cache');
      await dotCacheDir.create(recursive: true);

      const expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${dotCacheDir.path}/$expectedFileName');

      // Write mock HTML
      await cacheFile.writeAsString('''
<!DOCTYPE html>
<html>
<head>
  <title>Mock Title</title>
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video from CLI Output Cache</h1>
    <p>Mock description text</p>
  </li>
  <section id="transcript-content">
    <p>
      <span class="sentence">This is a mock transcript sentence to prevent skipping.</span>
    </p>
  </section>
</body>
</html>
''');

      final scriptPath = p.absolute('bin/flutter_wwdc_insights.dart');
      final customOutputDir = Directory('${tempDir.path}/custom_output');

      // Run the CLI with --output
      final result = await Process.run(
        Platform.executable,
        [
          scriptPath,
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
          '--output',
          customOutputDir.path,
        ],
        environment: {
          'WWDC_GEMINI_API_KEY': '',
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Output directory: ${customOutputDir.path}'));

      // Check that the output file is in the custom output directory
      final expectedOutputFile = File('${customOutputDir.path}/developer_apple_com_videos_play_wwdc2025_238.md');
      expect(await expectedOutputFile.exists(), isTrue);

      final outputContent = await expectedOutputFile.readAsString();
      expect(outputContent, contains('# Mock WWDC Video from CLI Output Cache'));

      tempDir.deleteSync(recursive: true);
    });

    test('CLI with --parse-only runs successfully and skips AI analysis', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_cli_parse_only_test');
      final dotCacheDir = Directory('${tempDir.path}/html_cache');
      await dotCacheDir.create(recursive: true);

      const expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${dotCacheDir.path}/$expectedFileName');

      // Write mock HTML
      await cacheFile.writeAsString('''
<!DOCTYPE html>
<html>
<head>
  <title>Mock Title</title>
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video for Parse Only</h1>
    <p>Mock description text</p>
  </li>
  <section id="transcript-content">
    <p>
      <span class="sentence">This is a mock transcript sentence to prevent skipping.</span>
    </p>
  </section>
</body>
</html>
''');

      final scriptPath = p.absolute('bin/flutter_wwdc_insights.dart');

      // Run the CLI with --parse-only
      final result = await Process.run(
        Platform.executable,
        [
          scriptPath,
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
          '--parse-only',
        ],
        environment: {
          'WWDC_GEMINI_API_KEY': 'mock_key',
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Output directory: output/parsed'));
      expect(result.stdout, contains('Parsing sessions...'));
      expect(result.stdout, isNot(contains('Running AI analysis')));
      expect(result.stdout, isNot(contains('Notice: No GEMINI_API_KEY found')));

      // Check that the output file is in the default parsed directory
      final expectedOutputFile = File('${tempDir.path}/output/parsed/developer_apple_com_videos_play_wwdc2025_238.md');
      expect(await expectedOutputFile.exists(), isTrue);

      final outputContent = await expectedOutputFile.readAsString();
      expect(outputContent, contains('# Mock WWDC Video for Parse Only'));
      expect(outputContent, isNot(contains('## AI Relevance & Importance Analysis')));

      tempDir.deleteSync(recursive: true);
    });

    test('CLI with --parse-only and single session video prints the absolute path of output md file', () async {
      final tempDir = Directory.systemTemp.createTempSync('wwdc_cli_parse_only_path_test');
      final dotCacheDir = Directory('${tempDir.path}/html_cache');
      await dotCacheDir.create(recursive: true);

      const expectedFileName = 'developer_apple_com_videos_play_wwdc2025_238.html';
      final cacheFile = File('${dotCacheDir.path}/$expectedFileName');

      // Write mock HTML
      await cacheFile.writeAsString('''
<!DOCTYPE html>
<html>
<head>
  <title>Mock Title</title>
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video for Path Test</h1>
    <p>Mock description text</p>
  </li>
  <section id="transcript-content">
    <p>
      <span class="sentence">This is a mock transcript sentence to prevent skipping.</span>
    </p>
  </section>
</body>
</html>
''');

      final scriptPath = p.absolute('bin/flutter_wwdc_insights.dart');

      // Run the CLI with --parse-only
      final result = await Process.run(
        Platform.executable,
        [
          scriptPath,
          '--url',
          'https://developer.apple.com/videos/play/wwdc2025/238/',
          '--parse-only',
        ],
        environment: {
          'WWDC_GEMINI_API_KEY': 'mock_key',
        },
        workingDirectory: tempDir.path,
      );

      expect(result.exitCode, equals(0));
      final expectedOutputFile = File('${tempDir.path}/output/parsed/developer_apple_com_videos_play_wwdc2025_238.md');
      expect(result.stdout, contains(expectedOutputFile.absolute.path));

      tempDir.deleteSync(recursive: true);
    });

    test('Extracts transcript from HLS subtitles when page transcript is missing', () async {
      final mockHtmlWithoutTranscript = '''
<!DOCTYPE html>
<html>
<head>
  <title>Mock WWDC Video Without Transcript</title>
  <meta property="og:video" content="https://devstreaming-cdn.apple.com/videos/wwdc/2026/258/4/66/cmaf.m3u8" />
</head>
<body>
  <li class="supplement details">
    <h1>Mock WWDC Video</h1>
    <p>Mock About Description</p>
  </li>
</body>
</html>
''';

      const mockMasterManifest = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="en",NAME="English",AUTOSELECT=YES,DEFAULT=YES,URI="subtitles/en/prog_index.m3u8",FORCED=NO
''';

      const mockSubtitlePlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXTINF:6.0
sequence_0.webvtt
#EXTINF:6.0
sequence_1.webvtt
#EXT-X-ENDLIST
''';

      const mockVtt0 = '''
WEBVTT

00:00:00.000 --> 00:00:06.000
Hello, this is the first segment of the video.
We are talking about version 2.5 of Xcode.
''';

      const mockVtt1 = '''
WEBVTT

00:00:06.000 --> 00:00:12.000
And here is the second segment.
Have a nice day!
''';

      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        final path = request.url.toString();
        if (path == 'https://developer.apple.com/videos/play/wwdc2026/258/') {
          return http.Response(mockHtmlWithoutTranscript, 200);
        } else if (path == 'https://devstreaming-cdn.apple.com/videos/wwdc/2026/258/4/66/cmaf.m3u8') {
          return http.Response(mockMasterManifest, 200);
        } else if (path == 'https://devstreaming-cdn.apple.com/videos/wwdc/2026/258/4/66/subtitles/en/prog_index.m3u8') {
          return http.Response(mockSubtitlePlaylist, 200);
        } else if (path == 'https://devstreaming-cdn.apple.com/videos/wwdc/2026/258/4/66/subtitles/en/sequence_0.webvtt') {
          return http.Response(mockVtt0, 200);
        } else if (path == 'https://devstreaming-cdn.apple.com/videos/wwdc/2026/258/4/66/subtitles/en/sequence_1.webvtt') {
          return http.Response(mockVtt1, 200);
        }
        return http.Response('Not Found', 404);
      });

      final parser = WwdcParser(
        cacheDirectory: null, // disable caching to force client fetches
        httpClient: mockClient,
      );

      final insights = await parser.parseUrl('https://developer.apple.com/videos/play/wwdc2026/258/');

      expect(insights.transcript.length, equals(1));
      expect(insights.transcript[0].sentences.length, equals(4));
      expect(insights.transcript[0].sentences[0], equals('Hello, this is the first segment of the video.'));
      expect(insights.transcript[0].sentences[1], equals('We are talking about version 2.5 of Xcode.'));
      expect(insights.transcript[0].sentences[2], equals('And here is the second segment.'));
      expect(insights.transcript[0].sentences[3], equals('Have a nice day!'));
      expect(requestCount, equals(5));
    });
  });
}
