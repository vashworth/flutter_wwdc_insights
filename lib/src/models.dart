class WwdcChapter {
  final int index;
  final String title;
  final int startTime;
  final int endTime;
  final int length;

  WwdcChapter({
    required this.index,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.length,
  });

  @override
  String toString() {
    return 'WwdcChapter(index: $index, title: "$title", startTime: ${startTime}s)';
  }
}

class WwdcResource {
  final String title;
  final String url;
  final String type; // 'document' or 'download'

  WwdcResource({
    required this.title,
    required this.url,
    required this.type,
  });

  @override
  String toString() {
    return 'WwdcResource(title: "$title", type: $type, url: $url)';
  }
}

class WwdcRelatedVideo {
  final String title;
  final String url;
  final String collection; // e.g., WWDC25

  WwdcRelatedVideo({
    required this.title,
    required this.url,
    required this.collection,
  });

  @override
  String toString() {
    return 'WwdcRelatedVideo(title: "$title", collection: $collection, url: $url)';
  }
}

class WwdcChapterSummary {
  final String chapterTitle;
  final int startTime;
  final String content;

  WwdcChapterSummary({
    required this.chapterTitle,
    required this.startTime,
    required this.content,
  });

  @override
  String toString() {
    return 'WwdcChapterSummary(title: "$chapterTitle", startTime: ${startTime}s)';
  }
}

class WwdcTranscriptParagraph {
  final List<String> sentences;

  WwdcTranscriptParagraph({
    required this.sentences,
  });

  String get fullText => sentences.join(' ');

  @override
  String toString() {
    return fullText;
  }
}

class WwdcCodeSnippet {
  final String description;
  final int startTime;
  final String code;

  WwdcCodeSnippet({
    required this.description,
    required this.startTime,
    required this.code,
  });

  @override
  String toString() {
    return 'WwdcCodeSnippet(description: "$description", startTime: ${startTime}s)';
  }
}

class WwdcVideoInsights {
  final String url;
  final String title;
  final String aboutDescription;
  final List<WwdcChapter> chapters;
  final List<WwdcResource> resources;
  final List<WwdcRelatedVideo> relatedVideos;
  final List<WwdcChapterSummary> summary;
  final List<WwdcTranscriptParagraph> transcript;
  final List<WwdcCodeSnippet> codeSnippets;

  WwdcVideoInsights({
    required this.url,
    required this.title,
    required this.aboutDescription,
    required this.chapters,
    required this.resources,
    required this.relatedVideos,
    required this.summary,
    required this.transcript,
    required this.codeSnippets,
  });

  /// Generates a sanitized base filename from the [url].
  String get cacheFileName {
    final sanitized = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized;
  }

  /// Generates a beautiful markdown representation of the parsed insights.
  String toMarkdown() {
    final sb = StringBuffer();
    sb.writeln('# $title');
    sb.writeln();
    sb.writeln('Source URL: [$url]($url)');
    sb.writeln();

    if (aboutDescription.isNotEmpty) {
      sb.writeln('## About');
      sb.writeln(aboutDescription);
      sb.writeln();
    }

    if (chapters.isNotEmpty) {
      sb.writeln('## Chapters');
      for (final ch in chapters) {
        sb.writeln('- Chapter ${ch.index}: ${ch.title} (${ch.startTime}s - ${ch.endTime}s)');
      }
      sb.writeln();
    }

    if (resources.isNotEmpty) {
      sb.writeln('## Resources');
      for (final res in resources) {
        sb.writeln('- [${res.title}](${res.url}) [${res.type}]');
      }
      sb.writeln();
    }

    if (relatedVideos.isNotEmpty) {
      sb.writeln('## Related Videos');
      for (final vid in relatedVideos) {
        sb.writeln('- **${vid.collection}** - [${vid.title}](${vid.url})');
      }
      sb.writeln();
    }

    if (summary.isNotEmpty) {
      sb.writeln('## Chapter Summaries');
      for (final sum in summary) {
        sb.writeln('### ${sum.chapterTitle} (starts at ${sum.startTime}s)');
        sb.writeln(sum.content);
        sb.writeln();
      }
    }

    if (codeSnippets.isNotEmpty) {
      sb.writeln('## Code Snippets');
      for (final snippet in codeSnippets) {
        sb.writeln('### ${snippet.description} (starts at ${snippet.startTime}s)');
        sb.writeln('```swift');
        sb.writeln(snippet.code.trim());
        sb.writeln('```');
        sb.writeln();
      }
    }

    if (transcript.isNotEmpty) {
      sb.writeln('## Transcript');
      for (final p in transcript) {
        sb.writeln(p.fullText);
        sb.writeln();
      }
    }

    return sb.toString();
  }
}
