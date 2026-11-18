import 'package:openlauncher_domain/entities/entity_action.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/modules/module.dart';
import 'package:openlauncher_domain/nodes/node.dart';

/// Where its live values come from, laid over its variables: a `source`
/// (an address, or a source of its pack), or one written `inline`.
const feedModule = ModuleType('feed', 'Feed', use: ModuleUse.generated);

extension NodeFeed on Node {
  Feed? get feed => switch (values(feedModule.name)) {
    {'source': final String name} && final values => Feed(
      name,
      inline: switch (values['inline']) {
        final Map<Object?, Object?> inline => jsonStringKeyed(inline),
        _ => null,
      },
      shared: switch (values['shared']) {
        final String shared => shared,
        _ => null,
      },
    ),
    {'inline': final Map<Object?, Object?> inline} => Feed.inline(
      jsonStringKeyed(inline),
    ),
    _ => null,
  };

  /// With [feed] as its feed; null removes it.
  Node withFeed(Feed? feed) => withModule(feedModule.name, switch (feed) {
    null => null,
    Feed(:final String name) => {
      'source': name,
      'inline': ?feed.inline,
      'shared': ?feed.shared,
    },
    Feed(:final inline?) => {'inline': inline},
    _ => null,
  });
}
