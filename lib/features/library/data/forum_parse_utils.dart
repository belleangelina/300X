import 'package:html/dom.dart' as dom;

String normalizeForumText(String value)
{
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\t\r\n ]+'), ' ')
        .trim();
}

int? queryInt(Uri uri, String name)
{
    for (final String component in uri.query.split('&'))
    {
        final int separator = component.indexOf('=');
        if (separator < 0 || component.substring(0, separator) != name)
        {
            continue;
        }
        final String value = component.substring(separator + 1);
        final int? direct = int.tryParse(value);
        if (direct != null)
        {
            return direct;
        }
        try
        {
            return int.tryParse(Uri.decodeQueryComponent(value));
        }
        on FormatException
        {
            return null;
        }
    }
    return null;
}

int parseForumCount(String value)
{
    final String normalized = normalizeForumText(value)
        .replaceAll(',', '')
        .toLowerCase();
    final Match? match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(
        normalized,
    );
    if (match == null)
    {
        return 0;
    }

    final double number = double.tryParse(match.group(1) ?? '') ?? 0;
    if (normalized.contains('万') || normalized.contains('w'))
    {
        return (number * 10000).round();
    }
    if (normalized.contains('千') || normalized.contains('k'))
    {
        return (number * 1000).round();
    }
    return number.round();
}

DateTime? parseForumTime(String value)
{
    final Match? match = RegExp(
        r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(value);
    if (match == null)
    {
        return null;
    }

    return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
    );
}

String directText(dom.Element? element)
{
    if (element == null)
    {
        return '';
    }
    return normalizeForumText(
        element.nodes
            .whereType<dom.Text>()
            .map((dom.Text node) => node.data)
            .join(' '),
    );
}
