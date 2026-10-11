import 'package:openlauncher/core/config/migrations/save_json.dart';

/// `sources` becomes `entities`: a web address is an entity with an `http`
/// feed, fixed text one with `data.text`.
void sourcesToEntities(Json save, Device device) {
  final sources = save.remove('sources');
  if (sources is! List) return;
  save['entities'] = [
    for (final source in sources)
      if (source case {'id': final String id})
        {
          'id': id,
          'category': 'value',
          'label': switch (source['name']) {
            final String name when name.isNotEmpty => name,
            _ => id,
          },
          if (source['kind'] == 'text')
            'data': {
              'text': switch (source['text']) {
                final String text => text,
                _ => '',
              },
            }
          else
            'feed': {
              'from': 'http',
              'url': switch (source['url']) {
                final String url => url,
                _ => '',
              },
              'every': switch (source['every']) {
                final num every => every,
                _ => 60,
              },
            },
        },
  ];
}
