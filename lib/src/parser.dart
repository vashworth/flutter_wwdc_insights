import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'models.dart';

class WwdcParser {
  /// Directory where fetched HTML pages are cached.
  /// If set to null, caching is disabled.
  final String? cacheDirectory;

  /// Optional HTTP client. If null, a new [http.Client] is created for the request.
  final http.Client? httpClient;

  WwdcParser({this.cacheDirectory = '.cache', this.httpClient});

  /// Fetches and parses the WWDC video page at [url].
  /// If [cacheDirectory] is specified, caching is used.
  Future<WwdcVideoInsights> parseUrl(String url) async {
    final htmlContent = await _getHtml(url);
    return parseHtml(htmlContent, url: url);
  }

  /// Fetches the HTML at [listUrl], parses all session links (e.g., starting with `/videos/play/`),
  /// and returns a list of unique absolute URLs.
  Future<List<String>> parseSessionUrls(String listUrl) async {
    final htmlContent = await _getHtml(listUrl);
    final document = html_parser.parse(htmlContent);
    final links = document.querySelectorAll('a[href^="/videos/play/"], a[href*="/videos/play/"]');
    final sessionUrls = <String>{};

    for (final link in links) {
      var href = link.attributes['href'];
      if (href != null && href.isNotEmpty) {
        if (!href.startsWith('http')) {
          if (href.startsWith('/')) {
            href = 'https://developer.apple.com$href';
          } else {
            final baseUri = Uri.parse(listUrl);
            href = baseUri.resolve(href).toString();
          }
        }
        sessionUrls.add(href);
      }
    }
    return sessionUrls.toList();
  }

  /// Fetches HTML content from [url], caching it if [cacheDirectory] is specified.
  Future<String> _getHtml(String url) async {
    if (cacheDirectory != null) {
      final cacheDir = Directory(cacheDirectory!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final fileName = _getCacheFileName(url);
      final cacheFile = File(p.join(cacheDir.path, fileName));

      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }

      final htmlContent = await _fetchUrl(url);
      await cacheFile.writeAsString(htmlContent);
      return htmlContent;
    }

    return _fetchUrl(url);
  }

  Future<String> _fetchUrl(String url) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch $url: StatusCode ${response.statusCode}');
      }
      return response.body;
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  String _getCacheFileName(String url) {
    // Sanitize URL to create a safe filename
    final sanitized = url
        .replaceAll(RegExp(r'https?://'), '') // remove protocol
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') // replace non-alphanumeric with _
        .replaceAll(RegExp(r'_+'), '_') // collapse multiple underscores
        .replaceAll(RegExp(r'^_|_$'), ''); // trim leading/trailing underscores
    return '$sanitized.html';
  }

  /// Parses raw HTML content of a WWDC video page.
  WwdcVideoInsights parseHtml(String html, {required String url}) {
    final document = html_parser.parse(html);

    // 1. Parse Title
    var title = document.querySelector('.supplement.details h1')?.text.trim();
    title ??= document.querySelector('title')?.text.trim();
    title ??= '';

    // 2. Parse About Description
    final aboutElement = document.querySelector('.supplement.details > p');
    final aboutDescription = aboutElement?.text.trim() ?? '';

    // 3. Parse Chapters
    final chapters = <WwdcChapter>[];
    final chapterItems = document.querySelectorAll('.supplement.details .chapter-list .chapter-item');
    for (final item in chapterItems) {
      final indexStr = item.attributes['data-chapter-index'] ?? '';
      final index = int.tryParse(indexStr) ?? 0;

      final startStr = item.attributes['data-start-time'] ?? '';
      final startTime = int.tryParse(startStr) ?? 0;

      final endStr = item.attributes['data-chapter-end-time'] ?? '';
      final endTime = int.tryParse(endStr) ?? 0;

      final lengthStr = item.attributes['data-chapter-lenght'] ?? '';
      final length = int.tryParse(lengthStr) ?? 0;

      final link = item.querySelector('a');
      final chapterTitle = link?.text.trim() ?? '';

      chapters.add(WwdcChapter(
        index: index,
        title: chapterTitle,
        startTime: startTime,
        endTime: endTime,
        length: length,
      ));
    }

    // 4. Parse Resources
    final resources = <WwdcResource>[];
    final resourceElements = document.querySelectorAll('.supplement.details ul.links > li');
    for (final element in resourceElements) {
      if (element.classes.contains('document')) {
        final link = element.querySelector('a');
        if (link != null) {
          resources.add(WwdcResource(
            title: link.text.trim(),
            url: link.attributes['href'] ?? '',
            type: 'document',
          ));
        }
      } else if (element.classes.contains('download')) {
        final optionLinks = element.querySelectorAll('.options li a');
        for (final optionLink in optionLinks) {
          resources.add(WwdcResource(
            title: optionLink.text.trim(),
            url: optionLink.attributes['href'] ?? '',
            type: 'download',
          ));
        }
        final directLink = element.querySelector('a');
        if (directLink != null && optionLinks.isEmpty) {
          resources.add(WwdcResource(
            title: directLink.text.trim(),
            url: directLink.attributes['href'] ?? '',
            type: 'download',
          ));
        }
      }
    }

    // 5. Parse Related Videos
    final relatedVideos = <WwdcRelatedVideo>[];
    final videoElements = document.querySelectorAll('.supplement.details li.video a');
    for (final a in videoElements) {
      String collection = '';
      var parent = a.parent;
      while (parent != null && !parent.classes.contains('supplement')) {
        var sibling = parent.previousElementSibling;
        while (sibling != null) {
          if (sibling.localName == 'h4' || sibling.localName == 'h3') {
            collection = sibling.text.trim();
            break;
          }
          sibling = sibling.previousElementSibling;
        }
        if (collection.isNotEmpty) break;
        parent = parent.parent;
      }

      var urlStr = a.attributes['href'] ?? '';
      if (urlStr.isNotEmpty && !urlStr.startsWith('http')) {
        urlStr = 'https://developer.apple.com$urlStr';
      }

      relatedVideos.add(WwdcRelatedVideo(
        title: a.text.trim(),
        url: urlStr,
        collection: collection,
      ));
    }

    // 6. Parse Summary
    final summaryList = <WwdcChapterSummary>[];
    final summaryContainer = document.querySelector('.supplement.summary');
    if (summaryContainer != null) {
      final items = summaryContainer.querySelectorAll('ul.no-bullet > li');
      String currentTitle = '';
      int currentStartTime = 0;

      for (final item in items) {
        if (item.classes.contains('chapter-summary')) {
          final paragraphs = item.querySelectorAll('p').map((e) => e.text.trim()).join('\n\n');
          summaryList.add(WwdcChapterSummary(
            chapterTitle: currentTitle,
            startTime: currentStartTime,
            content: paragraphs,
          ));
        } else {
          final link = item.querySelector('a');
          if (link != null) {
            currentTitle = link.text.trim();
            final startStr = link.attributes['data-start-time'] ?? '';
            currentStartTime = int.tryParse(startStr) ?? 0;
          } else {
            final text = item.text.trim();
            final parts = text.split(' - ');
            if (parts.length > 1) {
              currentTitle = parts.sublist(1).join(' - ');
              final timeParts = parts[0].split(':');
              if (timeParts.length == 2) {
                currentStartTime = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
              } else if (timeParts.length == 3) {
                currentStartTime = (int.tryParse(timeParts[0]) ?? 0) * 3600 + (int.tryParse(timeParts[1]) ?? 0) * 60 + (int.tryParse(timeParts[2]) ?? 0);
              }
            }
          }
        }
      }
    }

    // 7. Parse Transcript
    final transcriptParagraphs = <WwdcTranscriptParagraph>[];
    final transcriptSection = document.querySelector('#transcript-content');
    if (transcriptSection != null) {
      final paragraphs = transcriptSection.querySelectorAll('p');
      for (final p in paragraphs) {
        final sentences = <String>[];
        final sentenceSpans = p.querySelectorAll('span.sentence');
        for (final span in sentenceSpans) {
          final text = span.text.trim();
          if (text.isNotEmpty) {
            sentences.add(text);
          }
        }
        if (sentences.isNotEmpty) {
          transcriptParagraphs.add(WwdcTranscriptParagraph(sentences: sentences));
        }
      }
    }

    // 8. Parse Code Snippets
    final codeSnippets = <WwdcCodeSnippet>[];
    final codeContainers = document.querySelectorAll('.supplement.sample-code .sample-code-main-container');
    for (final container in codeContainers) {
      final link = container.querySelector('p a.jump-to-time-sample');
      final description = link?.text.trim() ?? '';

      final startStr = link?.attributes['data-start-time'] ?? '';
      final startTime = int.tryParse(startStr) ?? 0;

      final codeElem = container.querySelector('pre.code-source code');
      final codeText = codeElem?.text ?? '';

      codeSnippets.add(WwdcCodeSnippet(
        description: description,
        startTime: startTime,
        code: codeText,
      ));
    }

    return WwdcVideoInsights(
      url: url,
      title: title,
      aboutDescription: aboutDescription,
      chapters: chapters,
      resources: resources,
      relatedVideos: relatedVideos,
      summary: summaryList,
      transcript: transcriptParagraphs,
      codeSnippets: codeSnippets,
    );
  }
}
