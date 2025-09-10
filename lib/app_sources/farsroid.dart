import 'dart:convert';

import 'package:html/parser.dart';
import 'package:obtainium/app_sources/html.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:obtainium/components/generated_form.dart';
import 'package:easy_localization/easy_localization.dart';

class Farsroid extends AppSource {
  Farsroid() {
    hosts = ['farsroid.com'];
    name = 'Farsroid';
    additionalSourceAppSpecificSettingFormItems = [
      [
        GeneratedFormSwitch(
          'fallbackToOlderReleases',
          label: tr('fallbackToOlderReleases'),
          defaultValue: false,
        ),
      ],
    ];
  }

  @override
  String sourceSpecificStandardizeURL(String url, {bool forSelection = false}) {
    RegExp standardUrlRegEx = RegExp(
      '^https?://([^\\.]+\\.)${getSourceRegex(hosts)}/[^/]+',
      caseSensitive: false,
    );
    RegExpMatch? match = standardUrlRegEx.firstMatch(url);
    if (match == null) {
      throw InvalidURLError(name);
    }
    return match.group(0)!;
  }

  @override
  Future<APKDetails> getLatestAPKDetails(
    String standardUrl,
    Map<String, dynamic> additionalSettings,
  ) async {
    additionalSettings['skipSort'] = true;
    String appName = Uri.parse(standardUrl).pathSegments.last;

    var res = await sourceRequest(standardUrl, additionalSettings);
    if (res.statusCode != 200) {
      throw getObtainiumHttpError(res);
    }
    var html = parse(res.body);
    var dlinks = html.querySelectorAll('.download-links');
    if (dlinks.isEmpty) {
      throw NoReleasesError();
    }
    var postId = dlinks.first.attributes['data-post-id'] ?? '';
    var version = dlinks.first.attributes['data-post-version'] ?? '';

    if (postId.isEmpty || version.isEmpty) {
      throw NoVersionError();
    }

    var res2 = await sourceRequest(
      Uri.encodeFull(
        'https://${hosts[0]}/api/download-box/?post_id=$postId&post_version=$version',
      ),
      additionalSettings,
    );
    var html2 = jsonDecode(res2.body)?['data']?['content'] as String? ?? '';
    if (html2.isEmpty) {
      throw NoAPKError();
    }
    var apkLinks =
        (await grabLinksCommon(html2, res2.request!.url, additionalSettings))
            .map((l) => MapEntry(Uri.parse(l.key).pathSegments.last, l.key))
            .toList();

    if (apkLinks.isEmpty) {
      throw NoAPKError();
    }

    var fileNameSplitter = r'[-+()]+';
    var appName2 = apkLinks.first.key.split(RegExp(fileNameSplitter)).first;
    apkLinks = apkLinks.where(
              (l) => l.key.startsWith(
                RegExp('${getSourceRegex([appName2])}$fileNameSplitter'),
              ),
            )
            .toList();
    
    if (additionalSettings['fallbackToOlderReleases'] == false) {
      apkLinks = apkLinks.where(
              (l) => l.key.contains(
                RegExp('$fileNameSplitter${getSourceRegex([version])}$fileNameSplitter'),
              ),
            )
            .toList();
    }

    if (apkLinks.isEmpty) {
      throw NoAPKError();
    }

    return APKDetails(version, apkLinks, AppNames(name, appName));
  }
}
