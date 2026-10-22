#!/usr/bin/env node
// Generate Tinycast/Resources/DictationStart.wav and DictationStop.wav.
//
// Usage: node Scripts/gen-dictation-sounds.js
// Synthesized, so no third-party audio ships and every run writes the same bytes. Start rises a
// fourth and stop falls back down it; notes near 1 kHz stay clear in a headset's call profile.
"use strict";

const fs = require("fs");
const path = require("path");

const RATE = 44100;
const LENGTH = 0.4;
const G5 = 783.99;
const C6 = 1046.5;
const NOTE_GAP = 0.085;
const ATTACK = 0.006;
const FADE_OUT = 0.04;
const PEAK = 10 ** (-15 / 20);
const PARTIALS = [
  { ratio: 1, gain: 1, decay: 10 },
  { ratio: 2, gain: 0.22, decay: 16 },
  { ratio: 4, gain: 0.05, decay: 30 },
];

const SOUNDS = {
  DictationStart: [
    { at: 0, frequency: G5, gain: 0.8 },
    { at: NOTE_GAP, frequency: C6, gain: 1 },
  ],
  DictationStop: [
    { at: 0, frequency: C6, gain: 1 },
    { at: NOTE_GAP, frequency: G5, gain: 0.8 },
  ],
};

function render(notes) {
  const samples = new Float64Array(Math.round(LENGTH * RATE));
  for (const { at, frequency, gain } of notes) {
    for (let i = Math.round(at * RATE); i < samples.length; i++) {
      const t = i / RATE - at;
      const attack = t < ATTACK ? 0.5 - 0.5 * Math.cos((Math.PI * t) / ATTACK) : 1;
      let value = 0;
      for (const partial of PARTIALS) {
        value +=
          partial.gain * Math.exp(-partial.decay * t) * Math.sin(2 * Math.PI * frequency * partial.ratio * t);
      }
      samples[i] += gain * attack * value;
    }
  }
  const fadeStart = samples.length - Math.round(FADE_OUT * RATE);
  for (let i = fadeStart; i < samples.length; i++) {
    samples[i] *= 0.5 + 0.5 * Math.cos((Math.PI * (i - fadeStart)) / (samples.length - fadeStart));
  }
  const peak = samples.reduce((max, value) => Math.max(max, Math.abs(value)), 0);
  return samples.map((value) => (value / peak) * PEAK);
}

function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((value, i) => data.writeInt16LE(Math.round(value * 32767), i * 2));
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

for (const [name, notes] of Object.entries(SOUNDS)) {
  const file = path.join(__dirname, "..", "Tinycast", "Resources", `${name}.wav`);
  fs.writeFileSync(file, wav(render(notes)));
  console.log(`wrote ${path.relative(process.cwd(), file)}`);
}
