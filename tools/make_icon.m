#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 1;
        NSString *outPath = [NSString stringWithUTF8String:argv[1]];
        int size = 1024;

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:size
                          pixelsHigh:size
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:0];

        NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext setCurrentContext:nsCtx];
        CGContextRef ctx = nsCtx.CGContext;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

        // macOS squircle background
        CGRect iconR = CGRectMake(64, 64, size - 128, size - 128);
        CGPathRef squircle = CGPathCreateWithRoundedRect(iconR, 210, 210, NULL);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, squircle);
        CGContextClip(ctx);

        // Deep obsidian gradient backdrop
        CGFloat bgCols[] = {
            0.04, 0.05, 0.11, 1.0,
            0.10, 0.06, 0.20, 1.0,
            0.03, 0.04, 0.08, 1.0
        };
        CGGradientRef bgGrad = CGGradientCreateWithColorComponents(cs, bgCols, NULL, 3);
        CGContextDrawLinearGradient(ctx, bgGrad, CGPointMake(0, size), CGPointMake(size, 0), 0);
        CGGradientRelease(bgGrad);

        // Subtle ambient neon aura
        CGFloat auraCols[] = { 0.0, 0.90, 1.0, 0.28, 0.85, 0.12, 0.72, 0.12, 0.0, 0.0, 0.0, 0.0 };
        CGGradientRef auraGrad = CGGradientCreateWithColorComponents(cs, auraCols, NULL, 3);
        CGContextDrawRadialGradient(ctx, auraGrad, CGPointMake(512, 512), 40, CGPointMake(512, 512), 460, 0);
        CGGradientRelease(auraGrad);

        // Glowing Touch Bar OLED Pill in center
        CGRect barR = CGRectMake(144, 382, size - 288, 260);
        CGPathRef barPath = CGPathCreateWithRoundedRect(barR, 58, 58, NULL);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, barPath);
        CGContextSetRGBFillColor(ctx, 0.01, 0.01, 0.02, 0.98);
        CGContextFillPath(ctx);

        CGContextAddPath(ctx, barPath);
        CGContextClip(ctx);

        // Luminous plasma sine waves inside the Touch Bar pill
        for (int pass = 0; pass < 3; pass++) {
            CGContextBeginPath(ctx);
            for (int x = 144; x <= size - 144; x += 6) {
                double t = (double)(x - 144) / (double)(size - 288);
                double env = sin(t * M_PI);
                double y = 512.0 + sin(t * 14.0 + pass * 1.4) * (76.0 - pass * 14.0) * env;
                if (x == 144) CGContextMoveToPoint(ctx, x, y);
                else CGContextAddLineToPoint(ctx, x, y);
            }
            if (pass == 0) {
                CGContextSetRGBStrokeColor(ctx, 0.0, 0.95, 1.0, 0.45);
                CGContextSetLineWidth(ctx, 42.0);
            } else if (pass == 1) {
                CGContextSetRGBStrokeColor(ctx, 1.0, 0.14, 0.68, 0.78);
                CGContextSetLineWidth(ctx, 20.0);
            } else {
                CGContextSetRGBStrokeColor(ctx, 0.85, 0.98, 1.0, 0.98);
                CGContextSetLineWidth(ctx, 8.0);
            }
            CGContextStrokePath(ctx);
        }

        // LED equalizer mini-bars reflection
        for (int i = 0; i < 16; i++) {
            double bx = 186.0 + i * 42.0;
            double bh = 30.0 + fabs(sin(i * 0.75)) * 68.0;
            CGContextSetRGBFillColor(ctx, (double)i / 16.0, 0.88 - (double)i * 0.03, 1.0, 0.22);
            CGContextFillRect(ctx, CGRectMake(bx, 396, 22, bh));
        }
        CGContextRestoreGState(ctx);

        // Crisp glowing rim around Touch Bar pill
        CGContextAddPath(ctx, barPath);
        CGContextSetRGBStrokeColor(ctx, 0.25, 0.92, 1.0, 0.92);
        CGContextSetLineWidth(ctx, 9.0);
        CGContextStrokePath(ctx);
        CGPathRelease(barPath);

        // Subtle squircle outer glass edge
        CGContextRestoreGState(ctx);
        CGContextAddPath(ctx, squircle);
        CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.18);
        CGContextSetLineWidth(ctx, 6.0);
        CGContextStrokePath(ctx);
        CGPathRelease(squircle);
        CGColorSpaceRelease(cs);

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:outPath atomically:YES] ? 0 : 1;
    }
}
