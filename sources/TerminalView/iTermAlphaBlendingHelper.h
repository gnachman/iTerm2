//
//  iTermAlphaBlendingHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/20.
//

#import <Cocoa/Cocoa.h>

// Helper functions for computing the right alpha value for composited transparent views when
// you have a target *combined* transparency and a target blend, which is how visible the
// bottom view is relative to the top view.
//
// Specifically, the view hierarchy has an image view below a solid color background color view.
//
//   +-------+
//   | image |
// +-------+ |
// |  bg   |-+
// | color |
// +-------+
//
// The UI lets the user choose a target transparency. 0 = opaque, 1 = transparent.
// The UI also lets the user choose a blend level. 0 = pure bg color, 1 = pure image.
//
// Given these parameters, what is the appropriate alpha value for each view? Recall that the
// order of compositing matters:
//
//   UpdatedColor = SourceAlpha * SourceColor + (1 - SourceAlpha) * DestinationColor
//
// You can refactor this as:
//
//   UpdateColor = SourceAlpha * (SourceColor - DestinationColor) + DestinationColor
//
// Subtraction is not commutative, so it matters which is the source and which is the destination.
//
// Our target transparency `t` gives a relation between the alpha for the image (`a`) and
// the alpha for the background color (`b`) because the total transparency is the product of the
// alphas (this is commutative). Transparency is the inverse of alpha, so:
//
//   t = (1 - a) * (1 - b)
//
// We can write the formula for the desired color as:
//
//   UpdatedColor = b * BColor + (1 - b) * a * AColor
//
// From this you can see that BColor's contribution to the updated color is `b` and AColor's
// contribution is `(1 - b) * a`.
//
// Let us define their ratio as `q`:
//
//       (1 - b) * a
//   q = -----------
//            b
//
// We now have a system of equations:
//
//   (1) t = (1 - a) * (1 - b)
//
//           (1 - b) * a
//   (2) q = -----------
//                b
//
// Wolfram Alpha will kindly solve these for you. Ignoring the singularities:
//
//         1 - t            1 - t
//   a = q -----        b = -----
//         q + t            q + 1
//
// Now that we have a simple formula to calculate `a` and `b`, let's come up with a way to calculate
// `q`.
//
// We can compute the target value of q from our `blend` parameter, which we'll name `l`.
// When `l` is small, you want pure background color (big b) and when `l` is big you want
// pure image (small b). Specifically:
//
//   l=0   -> q=0           // Only background color makes a contribution.
//   l=0.5 -> q=1           // Equal parts image and background color contributions.
//   l=1   -> q=infinity    // Only image makes a contribution.
//
// The conversion from l to q follows this formula:
//
//         1
//   q = ----- - 1
//       1 - l
//
// There are infinitely many formulas that would suffice, but this one is simple and looks good.
//
// All that's left are the singularities:
//
// (1) Division by 0 when computing `q` when `l` equals 1 for `a`.
// (2) Division by 0 when computing `q` when `l` equals 1 for `b`.
// (3) Division by 0 when computing `a` when `q + t` equals 0.
//
// Problem (1) manifests as q diverging to infinity. We can compute the limit of a as q goes to
// infinity and use that for large l:
//
//            1 - t
//   lim    q ------ = 1 - t
//   q->∞     q + t
//
// For problem (2), a large `l` implies that `b` must be 0 (since we want to see only the background
// color).
//
// For problem (3), observe that while division by 0 only occurs when `t` is 0, the value of `a`
// must be 0 when `t > 0` and `l = 0` (because `q = 0` in that case). Generally:
//
//            1 - t
//   lim    q ------ = 0
//   q->0     q + t
//
// So when `l` is close to 1, we can simply return 0.

// Top view is `b`, the background color. `t` is target transparency. `l` is blend.
CGFloat iTermAlphaValueForTopView(CGFloat t, CGFloat l);

// Bottom view is `a`, the image. `t` is target transparency. `l` is blend.
CGFloat iTermAlphaValueForBottomView(CGFloat t, CGFloat l);
