import 'package:flutter/material.dart';

import '../../core/logging/logger.dart';
import '../../core/popup/popup_manager.dart';
import '../../core/routing/route_manager.dart';
import 'controlled_view.dart';

/// Base class for view controllers.
///
/// Every view controller should extend this class as an example as below.
///
/// ```dart
/// class FooController extends Controller {
///   FooController(super.logger);
///
///   @override
///   void onStart() {
///     super.onStart();
///     // Do something on start.
///   }
///
///   @override
///   void onClose() {
///     // Do something on close.
///     super.onClose();
///   }
///
///   // Method to be triggered by the corresponding view.
///   void foo() async {
///     context.read<FooCubit>().doSomething();
///     await routeManager.goRoute(context, 'exampleRoute');
///   }
/// }
/// ```
///
/// Then, register your controller in service locator as below.
///
/// ```dart
/// locator.registerFactory(
///   () => FooController(locator<Logger>()),
/// );
/// ```
///
/// A controller has a reflection of the corresponding view's lifecycle.
/// So, lifecycle events can be used to manage states of the view.
///
/// Additionally, BuildContext of the corresponding view is available
/// to the controller to be able to handle context related stuff such as
/// reading blocs/cubits, navigating between views, showing popups etc.
///
/// See also:
///
/// * [ControlledView], a base to components that construct views.
abstract class Controller<TParams extends Object> {
  Controller(this.logger, this.routeManager, this.popupManager);

  final _backgroundTimer = Stopwatch();
  bool _isActive = false;
  bool _isReady = false;
  bool _isVisible = false;

  /// Logger instance to be used in lifecycle events.
  @protected
  final Logger logger;

  /// RouteManager instance to be used for page navigation.
  @protected
  final RouteManager routeManager;

  /// PopupManager instance to be used for showing/hiding popups.
  @protected
  final PopupManager popupManager;

  /// The corresponding view's BuildContext.
  @protected
  late BuildContext context;

  /// An interface that is implemented by the corresponding view's state
  /// to be used by controllers such as AnimationController, TabController etc.
  @protected
  late TickerProvider vsync;

  /// Optional parameters that can be passed during navigation.
  @protected
  TParams? params;

  /// Indicates if the corresponding view is activated.
  @protected
  bool get isActive => _isActive;

  /// Indicates if the corresponding view is built and active.
  @protected
  bool get isReady => _isReady && _isActive;

  /// Indicates if the corresponding view is visible on screen.
  @protected
  bool get isVisible => _isVisible;

  /// Whether the corresponding view should be alive and keep its state.
  @protected
  bool get keepViewAlive => false;

  /// The last background time spent of the corresponding view.
  @protected
  Duration get backgroundTime => _backgroundTimer.elapsed;

  /// Called when the corresponding view is activated on start or resume.
  @protected
  @mustCallSuper
  void onActivate() {
    _isActive = true;
    _isVisible = true;
  }

  /// Called once when the corresponding view is initialized.
  @protected
  @mustCallSuper
  void onStart() {
    _isActive = true;
  }

  /// Called once when the corresponding view started and whenever
  /// the dependencies change.
  @protected
  @mustCallSuper
  void onPostStart() {
    _isActive = true;
  }

  /// Called after the corresponding view's build is finished.
  @protected
  @mustCallSuper
  void onReady() {
    _isReady = true;
  }

  /// Called when the corresponding view is visible back from pause.
  @protected
  @mustCallSuper
  void onResume() {
    _backgroundTimer.stop();
    _isActive = true;
  }

  /// Called when the corresponding view is visible on screen.
  @protected
  @mustCallSuper
  void onVisible() {
    _isVisible = true;
  }

  /// Called when the corresponding view is hidden on screen.
  @protected
  @mustCallSuper
  void onHidden() {
    _isVisible = false;
  }

  /// Called when the corresponding view goes invisible
  /// and running in the background.
  @protected
  @mustCallSuper
  void onPause() {
    _backgroundTimer.reset();
    _backgroundTimer.start();
    _isActive = false;
  }

  /// Called when the corresponding view is disposed. The difference between
  /// onStop and onClose is that onClose is called when the app is detached but
  /// onStop means the corresponding view is popped from the navigation stack.
  @protected
  @mustCallSuper
  void onStop() {
    _isActive = false;
  }

  /// Called when the app is detached which usually happens when
  /// back button is pressed.
  @protected
  @mustCallSuper
  void onClose() {
    _isReady = false;
  }

  /// Called when the corresponding view is deactivated on pause or close.
  @protected
  @mustCallSuper
  void onDeactivate() {
    _isActive = false;
  }

  /// Called when back button is pressed.
  @protected
  @mustCallSuper
  Future<bool> onBackRequest() => Future.value(true);
}
