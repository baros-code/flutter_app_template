// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:sliding_sheet2/sliding_sheet2.dart';

/// A tool to show/hide pre-defined or custom popups.
abstract class PopupManager {
  /// Shows a general dialog above the current contents of the app.
  /// [content] specifies the widget to be shown inside the dialog.
  /// [alignment] specifies the alignment of the dialog.
  /// [padding] adds a padding around the dialog.
  /// [barrierColor] specifies the color of the background barrier.
  /// [preventClose] prevents closing the dialog by pressing outside.
  /// [preventBackPress] prevents closing the dialog by pressing back button.
  Future<void> showPopup(
    BuildContext context,
    Widget content, {
    Alignment alignment,
    EdgeInsets padding,
    Color? barrierColor,
    bool preventClose,
    bool preventBackPress,
  });

  /// Shows a full screen dialog above the current contents of the app.
  /// [content] specifies the widget to be shown inside the dialog.
  /// [preventBackPress] prevents closing the dialog by pressing back button.
  Future<void> showFullScreenPopup(
    BuildContext context,
    Widget content, {
    bool preventBackPress,
  });

  /// Shows a bottom sheet dialog above the current contents of the app.
  /// [content] specifies the widget to be shown inside the dialog.
  /// [width] specifies the width of the dialog.
  /// [height] specifies the height of the dialog.
  /// [borderRadius] specifies the border radius of the dialog.
  /// [barrierColor] specifies the color of the background barrier.
  /// [preventClose] prevents closing the dialog by pressing outside.
  /// [preventBackPress] prevents closing the dialog by pressing back button.
  /// [enableDrag] enables dragging functionality of the dialog.
  Future<void> showBottomPopup(
    BuildContext context,
    Widget content, {
    double width,
    double height,
    double borderRadius,
    Color? barrierColor,
    bool preventClose,
    bool preventBackPress,
    bool enableDrag,
  });

  /// Shows a sliding bottom sheet dialog above the current contents of the app.
  /// [content] specifies the widget to be shown inside the dialog.
  /// [width] specifies the width of the dialog.
  /// [initialHeightSnap] specifies the initial height snap of the dialog.
  /// [heightSnaps] specifies height snaps that the dialog can be dragged to.
  /// [borderRadius] specifies the border radius of the dialog.
  /// [barrierColor] specifies the color of the background barrier.
  /// [elevation] specifies the elevation of the dialog.
  /// [dragIndicatorColor] specifies the color of the optional drag indicator
  /// on top of the dialog.
  /// [preventClose] prevents closing the dialog by pressing outside.
  /// [preventBackPress] prevents closing the dialog by pressing back button.
  Future<void> showSlidingBottomPopup(
    BuildContext context,
    Widget content, {
    double width,
    double? initialHeightSnap,
    List<double> heightSnaps,
    double borderRadius,
    Color? barrierColor,
    double elevation,
    Color? dragIndicatorColor,
    bool preventClose,
    bool preventBackPress,
    CustomSheetController? controller,
  });
}

class PopupManagerImpl implements PopupManager {
  @override
  Future<void> showPopup(
    BuildContext context,
    Widget content, {
    Alignment alignment = Alignment.center,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 20,
    ),
    Color? barrierColor,
    bool preventClose = false,
    bool preventBackPress = false,
  }) {
    return _showGeneralDialog(
      context,
      content,
      alignment: alignment,
      padding: padding,
      preventClose: preventClose,
      preventBackPress: preventBackPress,
      barrierColor: barrierColor,
      showFullScreen: false,
    );
  }

  @override
  Future<void> showFullScreenPopup(
    BuildContext context,
    Widget content, {
    bool preventBackPress = false,
  }) {
    return _showGeneralDialog(
      context,
      content,
      preventBackPress: preventBackPress,
      showFullScreen: true,
      enableSlideAnimation: true,
    );
  }

  @override
  Future<void> showBottomPopup(
    BuildContext context,
    Widget content, {
    double width = double.infinity,
    double height = double.infinity,
    double borderRadius = 0,
    Color? barrierColor,
    bool preventClose = false,
    bool preventBackPress = false,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet(
      context: context,
      enableDrag: enableDrag,
      isScrollControlled: enableDrag,
      isDismissible: !preventClose,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      barrierColor: barrierColor ?? Colors.black26,
      constraints: BoxConstraints(maxWidth: width, maxHeight: height),
      builder: (_) {
        return SafeArea(
          child: WillPopScope(
            onWillPop: () async => !preventBackPress,
            child: content,
          ),
        );
      },
    );
  }

  @override
  Future<void> showSlidingBottomPopup(
    BuildContext context,
    Widget content, {
    double width = double.infinity,
    double? initialHeightSnap,
    List<double> heightSnaps = const [double.infinity],
    double borderRadius = 25,
    Color? barrierColor,
    double elevation = 16,
    Color? dragIndicatorColor,
    bool preventClose = false,
    bool preventBackPress = false,
    CustomSheetController? controller,
  }) {
    return showSlidingBottomSheet(
      context,
      builder: (_) {
        final screenHeight =
            MediaQuery.of(context).orientation == Orientation.portrait
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.width;

        return SlidingSheetDialog(
          controller: controller?._sheetController,
          maxWidth: width,
          snapSpec: SnapSpec(
            initialSnap: initialHeightSnap != null
                ? initialHeightSnap / screenHeight
                : null,
            snappings: heightSnaps.map((s) => s / screenHeight).toList(),
          ),
          scrollSpec: const ScrollSpec(
            overscroll: false,
            physics: ClampingScrollPhysics(),
          ),
          duration: const Duration(milliseconds: 250),
          avoidStatusBar: true,
          // Work-around to make avoidStatusBar work.
          headerBuilder: (_, _) => const SizedBox.shrink(),
          cornerRadius: borderRadius,
          cornerRadiusOnFullscreen: 0,
          dismissOnBackdropTap: !preventClose,
          backdropColor: barrierColor ?? Colors.black26,
          elevation: elevation,
          builder: (context, state) {
            return SafeArea(
              top: false,
              child: WillPopScope(
                onWillPop: () async => !preventBackPress,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 50,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              dragIndicatorColor ??
                              Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                    content,
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helpers
  Future<void> _showGeneralDialog(
    BuildContext context,
    Widget content, {
    Alignment? alignment,
    EdgeInsets? padding,
    bool? preventClose,
    Color? barrierColor,
    required bool preventBackPress,
    required bool showFullScreen,
    bool enableSlideAnimation = false,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: preventClose != null ? !preventClose : true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor ?? Colors.black26,
      transitionBuilder: enableSlideAnimation
          ? (_, anim1, _, child) {
              return SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(anim1),
                child: child,
              );
            }
          : null,
      pageBuilder: (_, _, _) {
        return SafeArea(
          left: !showFullScreen,
          top: !showFullScreen,
          right: !showFullScreen,
          bottom: !showFullScreen,
          child: WillPopScope(
            onWillPop: () async => !preventBackPress,
            child: Align(
              alignment: alignment ?? Alignment.center,
              child: Padding(
                padding: showFullScreen
                    ? EdgeInsets.zero
                    : padding ?? EdgeInsets.zero,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }

  // - Helpers
}

class CustomSheetController {
  CustomSheetController();

  final SheetController _sheetController = SheetController();

  void expand() {
    _sheetController.expand();
  }
}
