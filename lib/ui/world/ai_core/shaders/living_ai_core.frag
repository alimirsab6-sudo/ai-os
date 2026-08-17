#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uMouse;
uniform float uHover;
uniform float uQuality;
uniform float uIntensity;
uniform float uSpeechIntensity;
uniform float uStateElapsed;
uniform float uIdle;
uniform float uListening;
uniform float uThinking;
uniform float uSpeaking;
uniform float uExecuting;
uniform float uSuccess;
uniform float uError;

out vec4 fragColor;

#define PI 3.14159265359

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
  return vec3(hash13(p), hash13(p + 19.19), hash13(p + 47.17));
}

mat2 rotate2d(float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return mat2(c, -s, s, c);
}

// Deterministic pseudo-voice: phrases contain pauses, unequal syllables,
// faster consonant-like peaks, and slow amplitude changes.
float speechEnvelope(float time) {
  float phrase = smoothstep(-0.24, 0.28,
    sin(time * 0.73) + sin(time * 0.29 + 1.8) * 0.42);
  float syllable = 0.28 + 0.72 * pow(abs(sin(time * 4.7 +
    sin(time * 1.37) * 1.2)), 0.72);
  float detail = 0.76 + 0.24 * sin(time * 11.3 + sin(time * 2.1));
  float burst = smoothstep(0.30, 0.92, sin(time * 2.43 + 0.7)) * 0.28;
  return clamp(phrase * syllable * detail + burst, 0.0, 1.0) *
    uSpeechIntensity;
}

// Inverse domain deformation. Sampling particles in this smoothly changing
// coordinate system makes them flow into the new form instead of scaling a
// rendered image. Each state affects different regions and axes.
vec3 morphDomain(vec3 world, float speech) {
  vec3 p = world;
  float time = uTime;
  float radius = length(p);
  vec3 direction = p / max(radius, 0.001);

  float slowLobe = sin(dot(direction, vec3(2.7, -1.9, 3.3)) * 2.1 +
    time * 0.31);
  float secondLobe = sin(dot(direction, vec3(-4.1, 3.7, 1.6)) * 1.8 -
    time * 0.23);
  float living = slowLobe * 0.045 + secondLobe * 0.026;

  // Listening opens toward the camera and tilts toward pointer activity.
  float front = smoothstep(-0.35, 0.82, direction.z);
  vec3 listeningAxes = vec3(
    1.0 + uListening * (0.035 + living),
    1.0 + uListening * (0.055 - living * 0.4),
    1.0 + uListening * (0.08 + front * 0.055)
  );

  // Speech never uses one global scale. Angular bands expand, compress, and
  // lag independently while the axes breathe at unequal rates.
  float speechBandA = sin(direction.y * 7.0 + direction.z * 4.0 - time * 4.1);
  float speechBandB = sin(direction.x * 5.0 - direction.z * 6.0 + time * 2.7);
  float regionalSpeech = speech * (0.13 + speechBandA * 0.075 +
    speechBandB * 0.045);
  vec3 speakingAxes = vec3(
    1.0 + uSpeaking * regionalSpeech * 1.05,
    1.0 + uSpeaking * regionalSpeech * 0.72,
    1.0 + uSpeaking * regionalSpeech * 1.28
  );

  // Thinking twists, offsets, and alternately elongates the upper/lower mass.
  float thoughtWave = sin(time * 0.83 + p.y * 2.8) * 0.5 + 0.5;
  p.xz = rotate2d(uThinking * (p.y * 0.19 + sin(time * 0.47) * 0.11)) * p.xz;
  p.x -= uThinking * (0.075 * sin(time * 0.61) +
    direction.y * thoughtWave * 0.055);
  vec3 thinkingAxes = vec3(
    1.0 + uThinking * (0.11 * thoughtWave - 0.025),
    1.0 + uThinking * (0.075 - 0.10 * thoughtWave),
    1.0 + uThinking * (0.10 * sin(time * 0.53 + 1.1))
  );

  // Executing reaches directionally, then recoils, foreshadowing future links
  // to spatial agents without rendering those agents yet.
  float taskCycle = 0.5 + 0.5 * sin(time * 1.18);
  float reach = uExecuting * (0.08 + taskCycle * 0.16);
  p.x -= reach * smoothstep(-0.6, 0.9, direction.x);
  vec3 executingAxes = vec3(1.0 + reach, 1.0 - reach * 0.28, 1.0 + reach * 0.16);

  float successPulse = uSuccess * exp(-uStateElapsed * 1.35) *
    sin(min(uStateElapsed * 3.3, PI));
  float errorPulse = uError * exp(-uStateElapsed * 1.75) *
    sin(min(uStateElapsed * 4.6, PI));
  vec3 eventAxes = vec3(1.0 + successPulse * 0.16 - errorPulse * 0.12);
  eventAxes.xy += vec2(errorPulse * 0.06, -errorPulse * 0.045);

  vec3 axes = listeningAxes * speakingAxes * thinkingAxes *
    executingAxes * eventAxes;
  p /= max(axes, vec3(0.58));

  // Permanent low-amplitude motion stops idle from becoming a resting globe.
  float localWarp = living + uThinking * sin(p.z * 4.7 - time * 0.92) * 0.055 +
    uSpeaking * speechBandA * speech * 0.07;
  p += direction * localWarp * (0.45 + radius * 0.35);
  p.xy += vec2(
    sin(p.y * 3.1 + p.z * 2.4 + time * 0.37),
    cos(p.x * 2.7 - p.z * 3.2 - time * 0.29)
  ) * (0.012 + uThinking * 0.025 + uSpeaking * speech * 0.022);
  return p;
}

float densityField(vec3 p, float time) {
  float low = sin(dot(p, vec3(1.31, 1.73, 1.17)) * 2.2 +
    sin(p.y * 2.7 - time * 0.19) + time * 0.12);
  float medium = sin(dot(p, vec3(-2.37, 3.11, 1.83)) * 3.5 +
    sin(p.z * 5.1 + time * 0.31));
  float high = sin(dot(p, vec3(5.73, -4.37, 6.17)) * 2.7 -
    time * 0.41 + sin(p.x * 7.3));
  return clamp(0.5 + low * 0.28 + medium * 0.15 + high * 0.07, 0.0, 1.0);
}

// A procedural population represents one set of independently phased points.
// The 3D spherical kernels project as points, while Z advection provides real
// forward/back motion and depth-dependent apparent size.
vec4 particlePopulation(
  vec3 world,
  float scale,
  float seed,
  float time,
  float zVelocity,
  float depth,
  float activity
) {
  vec3 q = world * scale;
  q.xy = rotate2d(seed * 0.071) * q.xy;
  q.xz = rotate2d(seed * 0.043 + 0.73) * q.xz;
  q.yz = rotate2d(seed * 0.029 - 0.51) * q.yz;
  q += vec3(
    sin(world.y * 3.1 + time * (0.21 + activity)) * 0.14,
    cos(world.x * 2.7 - time * (0.17 + activity * 0.7)) * 0.13,
    time * zVelocity
  );

  vec3 cell = floor(q);
  vec3 local = fract(q) - 0.5;
  vec3 random = hash33(cell + seed);
  float phase = random.x * PI * 2.0;
  float speed = (0.28 + random.y * 1.42) * activity;
  vec3 center = (random - 0.5) * 0.70;
  center += vec3(
    sin(time * speed + phase),
    cos(time * (0.37 + random.z) * activity + phase * 1.7),
    sin(time * (0.29 + random.x) * activity - phase * 1.3)
  ) * (0.052 + random.z * 0.065);

  float distanceToParticle = length(local - center);
  float rare = smoothstep(0.967, 0.998, random.z);
  float radius = mix(0.082, 0.198, depth) * mix(0.72, 1.34, random.x);
  radius *= mix(1.0, 1.82, rare);
  float gate = smoothstep(0.39, 0.91, hash13(cell + seed * 3.17));
  float sharp = (1.0 - smoothstep(radius * 0.60, radius * 1.36,
    distanceToParticle)) * gate;
  float glow = exp(-distanceToParticle * distanceToParticle /
    max(radius * radius * 8.7, 0.0001)) * gate;
  return vec4(sharp, glow, random.y, rare);
}

float energyStreams(vec3 p, float time) {
  vec2 pathA = vec2(
    sin(p.z * 2.4 + time * 0.46),
    cos(p.z * 1.8 - time * 0.34)
  ) * vec2(0.43, 0.32);
  vec2 pathB = vec2(
    cos(p.z * 2.9 - time * 0.31 + 1.7),
    sin(p.z * 2.2 + time * 0.40 - 0.8)
  ) * vec2(0.35, 0.47);
  float width = 37.0 - uThinking * 9.0 - uSpeaking * 5.0;
  return clamp(
    exp(-dot(p.xy - pathA, p.xy - pathA) * width) +
    exp(-dot(p.xy - pathB, p.xy - pathB) * (width + 6.0)) * 0.78,
    0.0,
    1.0
  );
}

vec3 palette(float seed, float depth, float density, float energy) {
  vec3 violet = vec3(0.18, 0.018, 0.43);
  vec3 purple = vec3(0.51, 0.045, 0.90);
  vec3 magenta = vec3(0.94, 0.07, 0.91);
  vec3 blue = vec3(0.035, 0.43, 1.0);
  vec3 cyan = vec3(0.16, 0.78, 1.0);
  vec3 lavender = vec3(0.82, 0.68, 1.0);
  float chroma = fract(seed + density * 0.39 + depth * 0.21);
  vec3 color = mix(violet, purple, smoothstep(0.03, 0.45, chroma));
  color = mix(color, magenta, smoothstep(0.40, 0.67, chroma));
  color = mix(color, blue, smoothstep(0.62, 0.89, chroma));
  color = mix(color, cyan, uListening * energy * 0.32);
  color = mix(color, lavender, energy * 0.25);
  color = mix(color, vec3(1.0, 0.025, 0.19), uError * 0.54);
  return color;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 screen = (frag - uResolution * 0.5) * 2.0 /
    max(uResolution.y, 1.0);
  screen.y *= -1.0;

  float speech = speechEnvelope(uTime);
  float activity = 1.0 + uListening * 0.18 + uThinking * 0.66 +
    uSpeaking * (0.30 + speech * 0.68) + uExecuting * 0.48;

  // Perspective camera and subtle pointer parallax. The camera shift is much
  // smaller than the local particle response below.
  vec2 cameraShift = uMouse * uHover * 0.035;
  vec3 rayOrigin = vec3(cameraShift, 2.82);
  vec3 rayTarget = vec3(cameraShift * 0.18, 0.0);
  vec3 rayDirection = normalize(vec3(screen * 0.82, -1.76) +
    vec3((rayTarget.xy - rayOrigin.xy) * 0.08, 0.0));
  float boundRadius = 1.34;
  float b = dot(rayOrigin, rayDirection);
  float c = dot(rayOrigin, rayOrigin) - boundRadius * boundRadius;
  float discriminant = b * b - c;
  if (discriminant <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  float root = sqrt(discriminant);
  float nearT = -b - root;
  float farT = -b + root;
  float stepCount = 30.0 + uQuality * 12.0;
  float stepLength = (farT - nearT) / stepCount;
  vec3 accumulatedColor = vec3(0.0);
  vec3 atmosphericGlow = vec3(0.0);
  float accumulatedAlpha = 0.0;

  for (int sampleIndex = 0; sampleIndex < 54; sampleIndex++) {
    float index = float(sampleIndex);
    if (index >= stepCount) continue;
    float rayT = nearT + (index + 0.5) * stepLength;
    vec3 world = rayOrigin + rayDirection * rayT;
    float depth = clamp((world.z / boundRadius + 1.0) * 0.5, 0.0, 1.0);

    vec3 p = morphDomain(world, speech);

    // Depth layers rotate differently, preventing a single rigid globe motion.
    vec3 slowP = p;
    slowP.xz = rotate2d(uTime * 0.031 + p.y * 0.026) * slowP.xz;
    vec3 deepP = p;
    deepP.yz = rotate2d(-uTime * 0.019 + p.x * 0.032) * deepP.yz;

    // Local physical pointer field with stronger foreground displacement and
    // a Z push so interaction reads volumetrically.
    vec2 projected = world.xy * 1.76 / max(1.20, 2.82 - world.z);
    vec2 mouseDelta = projected - uMouse * 0.72;
    float mouseField = exp(-dot(mouseDelta, mouseDelta) * 10.5) * uHover;
    vec2 mouseDirection = normalize(mouseDelta + vec2(0.0001));
    slowP.xy += mouseDirection * mouseField * mix(0.016, 0.075, depth);
    deepP.xy += mouseDirection * mouseField * mix(0.008, 0.038, depth);
    slowP.z -= mouseField * mix(0.014, 0.082, depth);

    float radius = length(p);
    vec3 direction = p / max(radius, 0.001);
    float boundaryNoise =
      sin(dot(direction, vec3(2.3, 3.1, -1.7)) * 2.2 + uTime * 0.14) * 0.064 +
      sin(dot(direction, vec3(-5.1, 2.7, 4.3)) * 2.7 - uTime * 0.21) * 0.032 +
      sin(dot(direction, vec3(8.3, -7.1, 6.7)) * 2.1 + uTime * 0.33) * 0.016;
    float organicBoundary = 0.96 + boundaryNoise;
    float mainVolume = 1.0 - smoothstep(
      organicBoundary - 0.21,
      organicBoundary + 0.045,
      radius
    );
    float outerRegion = smoothstep(organicBoundary - 0.025,
      organicBoundary + 0.055, radius) *
      (1.0 - smoothstep(1.22, 1.33, radius));

    float cloudA = densityField(deepP * 1.13, uTime);
    float cloudB = densityField(slowP * 2.31 + 7.3, -uTime * 0.71);
    float density = clamp(cloudA * 0.71 + cloudB * 0.29, 0.0, 1.0);
    float darkGate = smoothstep(0.23, 0.70, density) *
      mix(0.34, 1.38, density);

    vec4 deep = particlePopulation(
      deepP, 11.0 + uQuality * 1.2, 17.3, uTime * 0.43,
      0.075, depth, 0.43 * activity
    );
    vec4 volume = particlePopulation(
      slowP, 14.7 + uQuality * 1.7, 83.7, uTime * 0.69,
      0.14, depth, 0.68 * activity
    );
    vec4 cluster = particlePopulation(
      p, 18.7 + uQuality * 1.9, 149.2, uTime * 0.86,
      -0.11, depth, 0.82 * activity
    );

    float stream = energyStreams(p, uTime * activity * 0.22);
    vec3 streamP = p;
    streamP.z += uTime * (0.13 + uExecuting * 0.12 + speech * 0.05);
    vec4 energyParticles = particlePopulation(
      streamP, 20.5 + uQuality * 1.6, 233.9, uTime,
      0.23, depth, activity
    );
    vec4 escape = particlePopulation(
      world, 8.8 + uQuality * 0.8, 317.4, uTime * 0.32,
      -0.052, depth, 0.38
    );

    float deepWeight = mainVolume * darkGate * (0.36 + (1.0 - depth) * 0.22);
    float volumeWeight = mainVolume * mix(0.24, 1.20, density);
    float clusterWeight = mainVolume * smoothstep(0.55, 0.82, density) * 1.48;
    float streamWeight = mainVolume * stream *
      (0.68 + uThinking * 0.82 + uExecuting * 0.62 + uSpeaking * speech * 0.55);
    float escapeWeight = outerRegion *
      smoothstep(0.86, 0.987, escape.z) * 0.46;

    float sharp = deep.x * deepWeight + volume.x * volumeWeight +
      cluster.x * clusterWeight + energyParticles.x * streamWeight +
      escape.x * escapeWeight;
    float soft = deep.y * deepWeight * 0.19 +
      volume.y * volumeWeight * 0.21 + cluster.y * clusterWeight * 0.31 +
      energyParticles.y * streamWeight * 0.28 + escape.y * escapeWeight * 0.12;
    float rare = max(max(volume.w, cluster.w), energyParticles.w);
    float seed = fract(volume.z * 7.13 + cluster.z * 5.17 +
      energyParticles.z * 3.71 + deep.z * 2.29 + depth * 0.23);
    float energy = clamp(sharp + stream * 0.34 + rare * 0.43 +
      mouseField * 0.34 + speech * uSpeaking * 0.22, 0.0, 1.0);
    vec3 sampleColor = palette(seed, depth, density, energy);

    float depthBrightness = mix(0.30, 1.27, depth);
    float sampleAlpha = clamp(sharp * depthBrightness * 0.45, 0.0, 0.78);
    accumulatedColor += (1.0 - accumulatedAlpha) * sampleColor *
      sharp * depthBrightness;
    accumulatedAlpha += (1.0 - accumulatedAlpha) * sampleAlpha;
    atmosphericGlow += sampleColor * soft * depthBrightness *
      (1.0 - accumulatedAlpha) * stepLength * 0.84;
  }

  vec3 color = accumulatedColor * 1.38 + atmosphericGlow * 1.74;
  color *= uIntensity;
  color = 1.0 - exp(-color * 1.22);
  color = pow(color, vec3(0.91));
  float alpha = clamp(max(accumulatedAlpha,
    max(max(color.r, color.g), color.b)), 0.0, 1.0);
  fragColor = vec4(color, alpha);
}
