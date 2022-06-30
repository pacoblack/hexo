---
title: View曝光监控
toc: true
date: 2022-06-30 11:22:13
tags:
- android
categories:
- android
---
如何检测RecyclerView显示面积超过一半且超过1.5s
<!--more-->
# 计算时间
```java
override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    exposeChecker.updateStartTime()
}

override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
    onExpose()
    exposeChecker.updateStartTime()
}

```
## 源码分析
上面两个方法会在页面绑定到window的时候被触发，核心源代码在ViewRootimp的  host.dispatchVisibilityAggregated(viewVisibility == View.VISIBLE); 被触发之后，host就是我们的Activity的DecorView。
```java
mChildHelper = new ChildHelper(new ChildHelper.Callback(){
            @Override
            public void addView(View child, int index) {
                if (VERBOSE_TRACING) {
                    TraceCompat.beginSection("RV addView");
                }
                RecyclerView.this.addView(child, index);
                if (VERBOSE_TRACING) {
                    TraceCompat.endSection();
                }
                dispatchChildAttached(child);
            }

            @Override
            public void attachViewToParent(View child, int index,
                    ViewGroup.LayoutParams layoutParams) {
                final ViewHolder vh = getChildViewHolderInt(child);
                if (vh != null) {
                    if (!vh.isTmpDetached() && !vh.shouldIgnore()) {
                        throw new IllegalArgumentException("Called attach on a child which is not"
                                + " detached: " + vh + exceptionLabel());
                    }
                    if (DEBUG) {
                        Log.d(TAG, "reAttach " + vh);
                    }
                    vh.clearTmpDetachFlag();
                }
                RecyclerView.this.attachViewToParent(child, index, layoutParams);
            }
}
```
ChildHelper是RecyclerView内部负责专门管理所有子View的一个帮助类。其中通过暴露了接口回调的方式让它和RecyclerView可以绑定到一起。其中我们可以看到当child的add，attach都会触发attachViewToParent，
```
protected void removeDetachedView(View child, boolean animate) {
      if (mTransition != null) {
          mTransition.removeChild(this, child);
      }

      if (child == mFocused) {
          child.clearFocus();
      }
      if (child == mDefaultFocus) {
          clearDefaultFocus(child);
      }
      if (child == mFocusedInCluster) {
          clearFocusedInCluster(child);
      }

      child.clearAccessibilityFocus();

      cancelTouchTarget(child);
      cancelHoverTarget(child);

      if ((animate && child.getAnimation() != null) ||
              (mTransitioningViews != null && mTransitioningViews.contains(child))) {
          addDisappearingView(child);
      } else if (child.mAttachInfo != null) {
          child.dispatchDetachedFromWindow();
      }

      if (child.hasTransientState()) {
          childHasTransientStateChanged(child, false);
      }

      dispatchViewRemoved(child);
  }

  protected void attachViewToParent(View child, int index, LayoutParams params) {
      child.mLayoutParams = params;

      if (index < 0) {
          index = mChildrenCount;
      }

      addInArray(child, index);

      child.mParent = this;
      child.mPrivateFlags = (child.mPrivateFlags & ~PFLAG_DIRTY_MASK
                      & ~PFLAG_DRAWING_CACHE_VALID)
              | PFLAG_DRAWN | PFLAG_INVALIDATED;
      this.mPrivateFlags |= PFLAG_INVALIDATED;

      if (child.hasFocus()) {
          requestChildFocus(child, child.findFocus());
      }
      dispatchVisibilityAggregated(isAttachedToWindow() && getWindowVisibility() == VISIBLE
              && isShown());
      notifySubtreeAccessibilityStateChangedIfNeeded();
  }

  @Override
  boolean dispatchVisibilityAggregated(boolean isVisible) {
      isVisible = super.dispatchVisibilityAggregated(isVisible);
      final int count = mChildrenCount;
      final View[] children = mChildren;
      for (int i = 0; i < count; i++) {
          // Only dispatch to visible children. Not visible children and their subtrees already
          // know that they aren't visible and that's not going to change as a result of
          // whatever triggered this dispatch.
          if (children[i].getVisibility() == VISIBLE) {
              children[i].dispatchVisibilityAggregated(isVisible);
          }
      }
      return isVisible;
  }
```
其中`dispatchVisibilityAggregated`就是我们最前面说的ViewRoot所触发的ViewGroup内的方法，会逐层向下view分发View的attach方法。那么也就是当RecyclerView的子控件被添加到RecyclerView上时，就会触发子view的`attachToWindow`方法。

View的detch方法是在哪里被触发的呢，这个就是要看recyclerview的另外一个方法了，就是 `tryGetViewHolderForPositionByDeadline`了。
```Java
@Nullable
       ViewHolder tryGetViewHolderForPositionByDeadline(int position,
               boolean dryRun, long deadlineNs) {
           if (position < 0 || position >= mState.getItemCount()) {
               throw new IndexOutOfBoundsException("Invalid item position " + position
                       + "(" + position + "). Item count:" + mState.getItemCount()
                       + exceptionLabel());
           }
           boolean fromScrapOrHiddenOrCache = false;
           ViewHolder holder = null;
           // 0) If there is a changed scrap, try to find from there
           if (mState.isPreLayout()) {
               holder = getChangedScrapViewForPosition(position);
               fromScrapOrHiddenOrCache = holder != null;
           }
           // 1) Find by position from scrap/hidden list/cache
           if (holder == null) {
               holder = getScrapOrHiddenOrCachedHolderForPosition(position, dryRun);
               if (holder != null) {
                   if (!validateViewHolderForOffsetPosition(holder)) {
                       // recycle holder (and unscrap if relevant) since it can't be used
                       if (!dryRun) {
                           // we would like to recycle this but need to make sure it is not used by
                           // animation logic etc.
                           holder.addFlags(ViewHolder.FLAG_INVALID);
                           if (holder.isScrap()) {
                               removeDetachedView(holder.itemView, false);
                               holder.unScrap();
                           } else if (holder.wasReturnedFromScrap()) {
                               holder.clearReturnedFromScrapFlag();
                           }
                           recycleViewHolderInternal(holder);
                       }
                       holder = null;
                   } else {
                       fromScrapOrHiddenOrCache = true;
                   }
               }
           }
           ........
           return holder;
       }
```
当ViewHolder要被回收的时候就会触发RecyclerView的`tryGetViewHolderForPositionByDeadline`这个方法，然后我们可以观察到当holder.isScrap()的时候会removeDetachedView(holder.itemView, false);而这个正好触发了子项的viewDetch方法。

# 计算面积
```kotlin
fun View.isCover(): Boolean {
    var view = this
    val currentViewRect = Rect()
    val partVisible: Boolean = view.getLocalVisibleRect(currentViewRect)
    val totalHeightVisible =
        currentViewRect.bottom - currentViewRect.top >= view.measuredHeight
    val totalWidthVisible =
        currentViewRect.right - currentViewRect.left >= view.measuredWidth
    val totalViewVisible = partVisible && totalHeightVisible && totalWidthVisible
    if (!totalViewVisible)
        return true
    while (view.parent is ViewGroup) {
        val currentParent = view.parent as ViewGroup
        if (currentParent.visibility != View.VISIBLE) //if the parent of view is not visible,return true
            return true

        val start = view.indexOfViewInParent(currentParent)
        for (i in start + 1 until currentParent.childCount) {
            val viewRect = Rect()
            view.getGlobalVisibleRect(viewRect)
            val otherView = currentParent.getChildAt(i)
            val otherViewRect = Rect()
            otherView.getGlobalVisibleRect(otherViewRect)
            if (Rect.intersects(viewRect, otherViewRect)) {
                //if view intersects its older brother(covered),return true
                return true
            }
        }
        view = currentParent
    }
    return false
}

fun View.indexOfViewInParent(parent: ViewGroup): Int {
    var index = 0
    while (index < parent.childCount) {
        if (parent.getChildAt(index) === this) break
        index++
    }
    return index
}
```
# 补充
当页面切换的情况下，会调用viewTree里面的`onWindowFocusChanged`这个方法
核心原理其实也是ViewRootImp的`handleWindowFocusChanged` 这个方法会向下分发是否脱离window的方法，然后当接受到IWindow.Stub接受到了WMS的信号之后，则会给ViewRootImp发送一个message，然后从ViewRootImp开始向下分发view变化的生命周期。
```
  override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (hasWindowFocus) {
            exposeChecker.updateStartTime()
        } else {
            onExpose()
        }
    }
```
