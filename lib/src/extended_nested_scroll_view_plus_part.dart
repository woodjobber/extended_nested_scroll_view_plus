part of 'extended_nested_scroll_view_plus.dart';

/// It may be include statusBarHeight ,pinned appbar height,pinned SliverPersistentHeader height
/// which are in NestedScrollViewHeaderSlivers
typedef NestedScrollViewPlusPinnedHeaderSliverHeightBuilder = double Function();

class _ExtendedNestedScrollCoordinator extends _NestedScrollCoordinator {
  _ExtendedNestedScrollCoordinator(
    ExtendedNestedScrollViewPlusState state,
    ScrollController? parent,
    VoidCallback onHasScrolledBodyChanged,
    bool floatHeaderSlivers,
    void Function(List<ScrollPosition>)? onInnerScroll,
    this.pinnedHeaderSliverHeightBuilder,
    this.onlyOneScrollInBody,
    this.resetPositionToZero,
    this.scrollDirection,
  ) : super(
          state,
          parent,
          onHasScrolledBodyChanged,
          floatHeaderSlivers,
          onInnerScroll,
        ) {
    final double initialScrollOffset = _parent?.initialScrollOffset ?? 0.0;

    _outerController = _ExtendedNestedScrollController(
      this,
      initialScrollOffset: initialScrollOffset,
      debugLabel: 'outer',
    );
    _innerController = _ExtendedNestedScrollController(
      this,
      initialScrollOffset: 0.0,
      debugLabel: 'inner',
      onInnerScroll: onInnerScroll,
    );
  }

  /// Get the total height of pinned header in NestedScrollView header.

  final NestedScrollViewPlusPinnedHeaderSliverHeightBuilder?
      pinnedHeaderSliverHeightBuilder;

  /// When [ExtendedNestedScrollView]'s body has [TabBarView]/[PageView] and
  /// their children have AutomaticKeepAliveClientMixin or PageStorageKey,
  /// [_innerController.nestedPositions] will have more one,
  /// will scroll all of scroll positions together.
  /// set [onlyOneScrollInBody] true to avoid it.

  final bool onlyOneScrollInBody;

  /// 重置位置
  ///
  final bool? resetPositionToZero;

  /// The axis along which the scroll view scrolls.
  ///
  /// Defaults to [Axis.vertical].
  final Axis scrollDirection;

  void Function(List<ScrollPosition>)? get onInnerScroll =>
      super._innerController.onInnerScroll;

  @override
  _ExtendedNestedScrollController get _innerController =>
      super._innerController as _ExtendedNestedScrollController;

  /// The [TabBarView]/[PageView] in body should perpendicular with The Axis of
  /// [ExtendedNestedScrollView].
  Axis get bodyScrollDirection =>
      scrollDirection == Axis.vertical ? Axis.horizontal : Axis.vertical;

  @override
  Iterable<_ExtendedNestedScrollPosition> get _innerPositions {
    if (resetPositionToZero == true && _onResetPositions?.call() == true) {
      return _innerController.nestedPositions;
    }
    if (_innerController.nestedPositions.length > 1 && onlyOneScrollInBody) {
      final Iterable<_ExtendedNestedScrollPosition> actived = _innerController
          .nestedPositions
          .where((_ExtendedNestedScrollPosition element) => element.isActived);
      if (actived.isEmpty) {
        for (final _ExtendedNestedScrollPosition scrollPosition
            in _innerController.nestedPositions) {
          // TODO(zmtzawqlp): throw exception even mounted is true
          // In order for an element to have a valid renderObject, it must be '
          //  'active, which means it is part of the tree.\n'
          //  'Instead, this element is in the $_lifecycleState state.\n'
          //  'If you called this method from a State object, consider guarding '
          //  'it with State.mounted.
          try {
            if (!(scrollPosition.context as ScrollableState).mounted) {
              continue;
            }
            final RenderObject? renderObject =
                scrollPosition.context.storageContext.findRenderObject();
            if (renderObject == null || !renderObject.attached) {
              continue;
            }

            final VisibilityInfo? visibilityInfo =
                ExtendedVisibilityDetector.of(
                    scrollPosition.context.storageContext);
            if (visibilityInfo != null && visibilityInfo.visibleFraction == 1) {
              return <_ExtendedNestedScrollPosition>[scrollPosition];
            }

            if (renderObjectIsVisible(renderObject, bodyScrollDirection)) {
              return <_ExtendedNestedScrollPosition>[scrollPosition];
            }
          } catch (e) {
            continue;
          }
        }
        return _innerController.nestedPositions;
      }

      return actived;
    } else {
      return _innerController.nestedPositions;
    }
  }

  /// Return whether renderObject is visible in parent
  bool childIsVisible(
    RenderObject parent,
    RenderObject renderObject,
  ) {
    bool visible = false;

    // The implementation has to return the children in paint order skipping all
    // children that are not semantically relevant (e.g. because they are
    // invisible).
    parent.visitChildrenForSemantics((RenderObject child) {
      if (renderObject == child) {
        visible = true;
      } else {
        visible = childIsVisible(child, renderObject);
      }
    });
    return visible;
  }

  bool renderObjectIsVisible(RenderObject renderObject, Axis axis) {
    final RenderViewport? parent = findParentRenderViewport(renderObject);
    if (parent != null && parent.axis == axis) {
      for (final RenderSliver childrenInPaint
          in parent.childrenInHitTestOrder) {
        return childIsVisible(childrenInPaint, renderObject) &&
            renderObjectIsVisible(parent, axis);
      }
    }
    return true;
  }

  RenderViewport? findParentRenderViewport(RenderObject? object) {
    if (object == null) {
      return null;
    }
    object = object.parent;
    while (object != null) {
      // only find in body
      if (object is _ExtendedRenderSliverFillRemainingWithScrollable) {
        return null;
      }
      if (object is RenderViewport) {
        return object;
      }
      object = object.parent;
    }
    return null;
  }

  @override
  void updateCanDrag({_NestedScrollPosition? position}) {
    double maxInnerExtent = 0.0;

    if (onlyOneScrollInBody &&
        position != null &&
        position.debugLabel == 'inner') {
      if (position.haveDimensions) {
        maxInnerExtent = math.max(
          maxInnerExtent,
          position.maxScrollExtent - position.minScrollExtent,
        );

        position.updateCanDrag(maxInnerExtent >
                (position.viewportDimension - position.maxScrollExtent) ||
            position.minScrollExtent != position.maxScrollExtent);
      }
    }
    if (!_outerPosition!.haveDimensions) {
      return;
    }

    bool innerCanDrag = false;
    for (final _NestedScrollPosition position in _innerPositions) {
      if (!position.haveDimensions) {
        return;
      }
      innerCanDrag = innerCanDrag
          // This refers to the physics of the actual inner scroll position, not
          // the whole NestedScrollView, since it is possible to have different
          // ScrollPhysics for the inner and outer positions.
          ||
          position.physics.shouldAcceptUserOffset(position);
    }
    _outerPosition!.updateCanDrag(innerCanDrag);
  }
}

class _ExtendedNestedScrollController extends _NestedScrollController {
  _ExtendedNestedScrollController(
    _ExtendedNestedScrollCoordinator super.coordinator, {
    super.initialScrollOffset,
    super.debugLabel,
    super.onInnerScroll,
  });

  @override
  _ExtendedNestedScrollCoordinator get coordinator =>
      super.coordinator as _ExtendedNestedScrollCoordinator;

  @override
  Iterable<_ExtendedNestedScrollPosition> get nestedPositions =>
      kDebugMode ? _debugNestedPositions : _releaseNestedPositions;

  Iterable<_ExtendedNestedScrollPosition> get _debugNestedPositions {
    return Iterable.castFrom<ScrollPosition, _ExtendedNestedScrollPosition>(
        positions);
  }

  Iterable<_ExtendedNestedScrollPosition> get _releaseNestedPositions sync* {
    yield* Iterable.castFrom<ScrollPosition, _ExtendedNestedScrollPosition>(
        positions);
  }

  @override
  void attach(ScrollPosition position) {
    assert(position is _NestedScrollPosition);
    super.attach(position);
    coordinator.updateParent();
    coordinator.updateCanDrag(position: position as _NestedScrollPosition);
    position.addListener(_scheduleUpdateShadow);
    _scheduleUpdateShadow();
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ExtendedNestedScrollPosition(
      coordinator: coordinator,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _ExtendedNestedScrollPosition extends _NestedScrollPosition {
  _ExtendedNestedScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.oldPosition,
    super.debugLabel,
    required _ExtendedNestedScrollCoordinator super.coordinator,
  });
  @override
  _ExtendedNestedScrollCoordinator get coordinator =>
      super.coordinator as _ExtendedNestedScrollCoordinator;

  @override
  void applyNewDimensions() {
    super.applyNewDimensions();
    coordinator.updateCanDrag(position: this);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (debugLabel == 'outer' &&
        coordinator.pinnedHeaderSliverHeightBuilder != null) {
      maxScrollExtent =
          maxScrollExtent - coordinator.pinnedHeaderSliverHeightBuilder!();
      maxScrollExtent = math.max(0.0, maxScrollExtent);
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  bool _isActived = false;
  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    //print('drag--$debugLabel');
    _isActived = true;
    return coordinator.drag(details, () {
      dragCancelCallback();
      _isActived = false;
      //print('dragCancel--$debugLabel');
    });
  }

  /// Whether is actived now
  bool get isActived {
    return _isActived;
  }
}

class _ExtendedSliverFillRemainingWithScrollable
    extends SingleChildRenderObjectWidget {
  const _ExtendedSliverFillRemainingWithScrollable({
    super.key,
    super.child,
  });

  @override
  _ExtendedRenderSliverFillRemainingWithScrollable createRenderObject(
          BuildContext context) =>
      _ExtendedRenderSliverFillRemainingWithScrollable();
}

class _ExtendedRenderSliverFillRemainingWithScrollable
    extends RenderSliverFillRemainingWithScrollable {}

class _ExtendedNestedInnerBallisticScrollActivity
    extends _NestedInnerBallisticScrollActivity {
  _ExtendedNestedInnerBallisticScrollActivity(
    super.coordinator,
    super.position,
    super.simulation,
    super.vsync,
    super.shouldIgnorePointer,
  );
  @override
  bool applyMoveTo(double value) {
    // https://github.com/flutter/flutter/pull/87801
    return delegate
        .setPixels(coordinator.nestOffset(value, delegate))
        .isPrecisionZero;
  }
}

extension ExtendedDoubleEx on double {
  bool get notZero => abs() > precisionErrorTolerance;
  bool get isPrecisionZero => abs() < precisionErrorTolerance;
}
