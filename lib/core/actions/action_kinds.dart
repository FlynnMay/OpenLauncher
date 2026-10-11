import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What an action is done to.
enum Needs {
  nothing,

  /// A card: an app, an input, or one of the launcher's own.
  card,

  /// A card that is an installed app.
  app,
}

/// What only the screen an action was set off on can do. There is none
/// where there is no screen, and such actions then do nothing.
abstract interface class ActionScreen {
  /// Shows the popup [panelId]; with a [subject], as that card's menu.
  Future<void> openPanel(String panelId, {LauncherCard? subject});

  Future<void> openSettings();

  /// Closes the popup the action was set off in.
  void close();
}

/// One action as it is being carried out.
class ActionRun {
  const ActionRun(this.ref, this.act, this.card, this.screen, this.held);

  final Ref ref;
  final Act act;

  /// What it is done to; never null for a kind that [Needs] one.
  final LauncherCard? card;
  final ActionScreen? screen;
  final bool held;

  LauncherPlatform get platform => ref.read(launcherPlatformProvider);
}

/// A kind of thing a button, a card or anything else on the screen can do.
///
/// **This list is the one place actions are defined.** The menu a held card
/// opens, the choices the editor offers and what a trigger carries out are
/// all read from it: a new action is a new entry here and nothing else.
class ActionKind {
  const ActionKind({
    required this.name,
    required this.label,
    required this.icon,
    required this.run,
    this.needs = Needs.nothing,
    this.args = const {},
  });

  /// How an [Act] names it.
  final String name;
  final String label;

  /// The name of the picture a button that does this starts with.
  final String icon;
  final Needs needs;

  /// What it is told beside the card, by the name of each, with what that
  /// is: `panel` (the id of a popup) or the choices there are.
  final Map<String, List<String>> args;

  /// Does it. Returns something to tell the user, if there is anything.
  final Future<String?> Function(ActionRun run) run;
}

/// The argument whose value is the id of a popup.
const panelArg = 'panel';

final List<ActionKind> actionKinds = [
  ActionKind(
    name: 'open',
    label: 'Open',
    icon: 'play',
    needs: Needs.card,
    run: (run) async {
      final card = run.card!;
      // The launcher's own screens; there is only the one so far.
      if (card.kind == CardKind.action) {
        await run.screen?.openSettings();
      } else {
        await run.ref.read(cardActionsProvider).launch(card);
      }
      return null;
    },
  ),
  ActionKind(
    name: 'menu',
    label: 'Quick actions',
    icon: 'menu',
    needs: Needs.card,
    run: (run) async {
      await run.screen?.openPanel(Layout.menuId, subject: run.card);
      return null;
    },
  ),
  ActionKind(
    name: 'info',
    label: 'App info',
    icon: 'info',
    needs: Needs.app,
    run: (run) async {
      await run.platform.openAppInfo(run.card!.target);
      return null;
    },
  ),
  ActionKind(
    name: 'forceStop',
    label: 'Force stop',
    icon: 'stop',
    needs: Needs.app,
    run: (run) async {
      final card = run.card!;
      if (await run.platform.forceStopApp(card.target)) {
        return '${card.label} was stopped.';
      }
      // The launcher could not do it; the TV's own screen can.
      await run.platform.openAppInfo(card.target);
      return 'Choose "Force stop" here. Run automatic setup in Settings '
          'to stop apps straight from the menu.';
    },
  ),
  ActionKind(
    name: 'uninstall',
    label: 'Uninstall',
    icon: 'delete',
    needs: Needs.app,
    run: (run) async {
      await run.platform.uninstallApp(run.card!.target);
      return null;
    },
  ),
  ActionKind(
    name: 'remove',
    label: 'Remove',
    icon: 'remove',
    needs: Needs.card,
    run: (run) async {
      final card = run.card!;
      await run.ref.read(configProvider.notifier).removeCard(card.id);
      return '${card.label} was removed. Add it again from the web page.';
    },
  ),
  ActionKind(
    name: 'panel',
    label: 'Open a folder',
    icon: 'folder',
    args: const {panelArg: []},
    run: (run) async {
      if (run.act.arg(panelArg) case final id?) {
        await run.screen?.openPanel(id);
      }
      return null;
    },
  ),
  ActionKind(
    name: 'settings',
    label: 'Launcher settings',
    icon: 'settings',
    run: (run) async {
      await run.screen?.openSettings();
      return null;
    },
  ),
  ActionKind(
    name: 'media',
    label: 'Play or pause',
    icon: 'pause',
    args: {
      'command': [for (final command in MediaCommand.values) command.name],
    },
    run: (run) async {
      await run.platform.sendMediaCommand(
        MediaCommand.values.asNameMap()[run.act.arg('command')] ??
            MediaCommand.playPause,
      );
      return null;
    },
  ),
  ActionKind(
    name: 'close',
    label: 'Close the popup',
    icon: 'close',
    run: (run) async {
      run.screen?.close();
      return null;
    },
  ),
];

/// The kind called [name]; none for one made by a newer launcher.
ActionKind? actionKind(String name) =>
    actionKinds.where((kind) => kind.name == name).firstOrNull;

final actionRunnerProvider = Provider<ActionRunner>(ActionRunner.new);

/// Carries actions out, for the TV's screen and for anything else.
class ActionRunner {
  ActionRunner(this._ref);

  final Ref _ref;

  /// Whether [act] can be done with [subject] as the card it was set off
  /// from. One that names its own card is taken at its word.
  bool applies(Act act, LauncherCard? subject) {
    final kind = actionKind(act.name);
    if (kind == null) return false;
    if (act.arg('card') != null) return true;
    return switch (kind.needs) {
      Needs.nothing => true,
      Needs.card => subject != null,
      Needs.app => subject?.kind == CardKind.app,
    };
  }

  /// Does [act] to the card it names, or failing that to [subject]. What
  /// cannot be done, for want of a card or of a [screen], is left undone.
  /// Returns something to tell the user, if there is anything.
  Future<String?> run(
    Act act, {
    LauncherCard? subject,
    ActionScreen? screen,
    bool held = false,
  }) async {
    final kind = actionKind(act.name);
    if (kind == null) return null;
    var card = subject;
    if (act.arg('card') case final id?) {
      final cards = await _ref.read(allCardsProvider.future);
      card = cards.where((card) => card.id == id).firstOrNull;
    }
    final fits = switch (kind.needs) {
      Needs.nothing => true,
      Needs.card => card != null,
      Needs.app => card?.kind == CardKind.app,
    };
    if (!fits) return null;
    return kind.run(ActionRun(_ref, act, card, screen, held));
  }
}
