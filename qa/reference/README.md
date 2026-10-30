# Screenshot style probes

`input.jpg` and `target.jpg` are cropped from the left/right comparison in the user-supplied screenshot of rohan (@hxkusho)'s post. They exclude the social-media interface. The input is a screenshot of an already developed image, not sensor RAW. The target is presented in the post as the app-shot example.

The scenes have different framing and may differ in exposure, capture time and processing. Compression, screenshots and display scaling further limit comparison. No pixelwise photographic-equivalence score is valid here.

The native test harness renders the input crop through Grainlight and saves the target alongside it for visual inspection. The target is never processed again. Other supplied examples (daylight Chicago, night walk, sunset and airport) guide the style but have no before images, so they cannot be used as input/target validation pairs.

The 30 October reference tuning deepens the tone curve, cools dark tones, warms bright neutrals, and reduces bright-blue chroma toward cream. Blue suppression is restricted by luminance to preserve dark blue architecture. Neutral mode still bypasses the creative LUT.

The supplied screenshot is tagged Display P3. Crops are converted through Pillow/LittleCMS to tagged sRGB before renderer evaluation; no P3 values are relabeled as sRGB.
