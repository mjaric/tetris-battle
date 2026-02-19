class SoundManager {
  private static instance: SoundManager;
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private volume = 0.5;
  private muted = false;
  private initialized = false;
  private activeSources = 0;
  private readonly MAX_CONCURRENT = 8;

  private constructor() {}

  static getInstance(): SoundManager {
    if (!SoundManager.instance) {
      SoundManager.instance = new SoundManager();
    }
    return SoundManager.instance;
  }

  init(): void {
    if (this.initialized) return;
    try {
      this.ctx = new AudioContext();
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.value = this.volume;
      this.masterGain.connect(this.ctx.destination);
      this.initialized = true;
    } catch {
      // Web Audio not supported
    }
  }

  private ensureContext(): AudioContext | null {
    if (!this.ctx) return null;
    if (this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => {});
    }
    return this.ctx;
  }

  private canPlay(): boolean {
    return this.initialized && !this.muted && this.activeSources < this.MAX_CONCURRENT;
  }

  private trackSource(source: AudioBufferSourceNode | OscillatorNode): void {
    this.activeSources++;
    source.onended = () => {
      this.activeSources = Math.max(0, this.activeSources - 1);
    };
  }

  // --- Synthesized sounds ---

  playMove(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(300, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(200, ctx.currentTime + 0.05);
    gain.gain.setValueAtTime(0.1, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.05);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.05);
  }

  playRotate(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(400, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(600, ctx.currentTime + 0.06);
    gain.gain.setValueAtTime(0.1, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.06);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.06);
  }

  playSoftDrop(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(250, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(150, ctx.currentTime + 0.03);
    gain.gain.setValueAtTime(0.06, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.03);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.03);
  }

  playHardDrop(distance: number): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Impact thud using noise
    const bufferSize = ctx.sampleRate * 0.15;
    const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.1));
    }

    const noise = ctx.createBufferSource();
    noise.buffer = buffer;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 200 + Math.min(distance, 20) * 30;

    const gain = ctx.createGain();
    const vol = Math.min(0.3, 0.1 + distance * 0.01);
    gain.gain.setValueAtTime(vol, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.15);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(noise);
    noise.start(ctx.currentTime);
    noise.stop(ctx.currentTime + 0.15);
  }

  playLineClear(count: number): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    if (count === 4) {
      // Tetris: powerful ascending chord
      const freqs = [261.6, 329.6, 392, 523.3]; // C4, E4, G4, C5
      freqs.forEach((freq, i) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'square';
        osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.05);
        gain.gain.setValueAtTime(0, ctx.currentTime);
        gain.gain.linearRampToValueAtTime(0.08, ctx.currentTime + i * 0.05);
        gain.gain.linearRampToValueAtTime(0.05, ctx.currentTime + 0.3);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5);
        osc.connect(gain);
        gain.connect(this.masterGain!);
        this.trackSource(osc);
        osc.start(ctx.currentTime + i * 0.05);
        osc.stop(ctx.currentTime + 0.5);
      });
    } else {
      // Normal clear: quick bright tone
      const baseFreq = 400 + count * 100;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'triangle';
      osc.frequency.setValueAtTime(baseFreq, ctx.currentTime);
      osc.frequency.exponentialRampToValueAtTime(baseFreq * 1.5, ctx.currentTime + 0.1);
      gain.gain.setValueAtTime(0.15, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.2);
      osc.connect(gain);
      gain.connect(this.masterGain);
      this.trackSource(osc);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.2);
    }
  }

  playCombo(count: number): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Rising pitch based on combo count
    const baseFreq = 300 + count * 80;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(baseFreq, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(baseFreq * 1.5, ctx.currentTime + 0.15);
    gain.gain.setValueAtTime(0.08, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.2);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.2);
  }

  playB2B(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Epic chord: two oscillators
    const freqs = [523.3, 659.3]; // C5, E5
    freqs.forEach((freq) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.1, ctx.currentTime);
      gain.gain.linearRampToValueAtTime(0.15, ctx.currentTime + 0.1);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.6);
      osc.connect(gain);
      gain.connect(this.masterGain!);
      this.trackSource(osc);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.6);
    });
  }

  playGarbageSent(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Whoosh: filtered noise sweep
    const bufferSize = ctx.sampleRate * 0.2;
    const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.3));
    }

    const noise = ctx.createBufferSource();
    noise.buffer = buffer;

    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(500, ctx.currentTime);
    filter.frequency.exponentialRampToValueAtTime(3000, ctx.currentTime + 0.15);
    filter.Q.value = 2;

    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.12, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.2);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(noise);
    noise.start(ctx.currentTime);
    noise.stop(ctx.currentTime + 0.2);
  }

  playGarbageReceived(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Low impact rumble
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(80, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(40, ctx.currentTime + 0.2);
    gain.gain.setValueAtTime(0.2, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.25);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.25);
  }

  playElimination(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    // Descending tone + noise burst
    const osc = ctx.createOscillator();
    const oscGain = ctx.createGain();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(600, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(100, ctx.currentTime + 0.4);
    oscGain.gain.setValueAtTime(0.12, ctx.currentTime);
    oscGain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
    osc.connect(oscGain);
    oscGain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.4);

    // Noise burst
    const bufferSize = ctx.sampleRate * 0.3;
    const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.15));
    }
    const noise = ctx.createBufferSource();
    noise.buffer = buffer;
    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.15, ctx.currentTime);
    noiseGain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3);
    noise.connect(noiseGain);
    noiseGain.connect(this.masterGain);
    this.trackSource(noise);
    noise.start(ctx.currentTime);
    noise.stop(ctx.currentTime + 0.3);
  }

  playDangerWarning(): void {
    const ctx = this.ensureContext();
    if (!ctx || !this.canPlay() || !this.masterGain) return;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'square';
    osc.frequency.setValueAtTime(200, ctx.currentTime);
    osc.frequency.setValueAtTime(150, ctx.currentTime + 0.1);
    gain.gain.setValueAtTime(0.05, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.2);
    osc.connect(gain);
    gain.connect(this.masterGain);
    this.trackSource(osc);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.2);
  }

  // --- Volume controls ---

  setVolume(v: number): void {
    this.volume = Math.max(0, Math.min(1, v));
    if (this.masterGain) {
      this.masterGain.gain.value = this.muted ? 0 : this.volume;
    }
  }

  getVolume(): number {
    return this.volume;
  }

  setMuted(m: boolean): void {
    this.muted = m;
    if (this.masterGain) {
      this.masterGain.gain.value = this.muted ? 0 : this.volume;
    }
  }

  isMuted(): boolean {
    return this.muted;
  }
}

export const soundManager = SoundManager.getInstance();
