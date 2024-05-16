(
~detectDirection = { | phase, low = -1, high = 1 |
	var current, previous, initialReset, reset, direction;
	current = phase;
    previous = Delay1.ar(current);
	initialReset = Trig1.ar(Impulse.ar(0), SampleDur.ir());
    reset = current < previous;
	reset = reset | initialReset;
	direction = Demand.ar(reset, 0, Dseq([high,low],inf));
	direction;
};

~phasorSync = { | freq, amp = 1, direction = 1, reset = 0, offset = 0 |
	var increment, phase;
	increment = (freq / SampleRate.ir) * amp;
	phase = Phasor.ar(
		rate: increment * direction,
		trig: reset,
		start: 0,
        end: amp
    );
	Wrap.ar(phase + offset, 0, amp);
};

~phasorSoftSync = { | freq, amp, direction, offset = 0 |
	var phase;
	~phasorSync.value(freq, amp, direction,0);
};

~phasorHardSync = { | freq, amp, reset, offset = 0 |
	var phase;
	~phasorSync.value(freq, amp, 1, reset);
};

~triOsc = { | phasor |
	Fold.ar(MulAdd(phasor, 4), -1, 1)
}
)

(
SynthDef(\pmSoftSyncPhasor, {|freq = 440, modFreq = 440, index = 1, amp = 1.0|
    var carrier_phase, carrier_increment;
	var direction;
	var modulator_phase;
	var out, fm_phase, fm_osc;

	carrier_increment = freq / SampleRate.ir *2 *pi;
    carrier_phase = Phasor.ar(0, carrier_increment, 0, 2 * pi);

	direction = ~detectDirection.value(carrier_phase);

	// half frequency since we'll fold later to create alternating direction ramp
	modulator_phase = ~phasorSoftSync.value(MulAdd(modFreq, 0.5), 4 * pi, direction);

	// eliminate discontinuities when index is not an integer by reversing instead of reseting
	// (reversing phasor is the same as a half frequency triangle)
	// TODO confirm this doesn't create discontinuties with 4pi period, move to a function
	modulator_phase = Fold.ar(modulator_phase,0.0,2*pi);

	fm_phase = modulator_phase*index+carrier_phase;
	fm_osc = SinOsc.ar(0, fm_phase);

	out = fm_osc;

	Out.ar(0, (out * 0.25) ! 2);
}).add;
)

(
SynthDef(\pmSoftSyncSin, {|freq = 440, modFreq = 440, index = 1, amp = 1.0|
    var carrier_phase, carrier_increment;
	var current, previous, reset, direction;
	var modulator_increment, modulator_osc, modulator_phase;
	var out, fm_phase, fm_osc;

	carrier_increment = freq / SampleRate.ir * 2 * pi;
    carrier_phase = Phasor.ar(0, carrier_increment, 0, 2 * pi);

	direction = ~detectDirection.value(carrier_phase);


    modulator_phase = ~phasorSoftSync.value(MulAdd(modFreq, 0.5), 4 * pi, direction);
    modulator_osc = SinOsc.ar(0, modulator_phase);

	fm_phase = (modulator_osc*2*pi*index)+carrier_phase;
	fm_osc = SinOsc.ar(0, fm_phase);

	out = fm_osc;

	Out.ar(0, (out * 0.25) ! 2);
}).add;
)

(
SynthDef(\testOscSync, {|freq = 120, modFreq = 220, hardSync = 0, softSync = 0, phasorFilter = 0 |
    var carrier_phase, carrier_increment;
	var direction, hard_sync_trigger, soft_sync_trigger;
	var modulator_increment, modulator_osc, modulator_phase, mod_unit;
	var out;

	carrier_increment = freq / SampleRate.ir * 2 * pi;
    carrier_phase = Phasor.ar(0, carrier_increment, 0, 2 * pi);

	direction = ~detectDirection.value(carrier_phase, 0, 1);
	hard_sync_trigger = hardSync * Changed.ar(direction);
	// scale direction for soft sync
	direction = direction * 2 - 1;
	soft_sync_trigger = Latch.ar(direction, 1 - softSync);
	// if soft sync is off, use the latched direction signal, otherwise use current direction signal
	// TODO this might cause a 1 cycle glitch when turned back on
	soft_sync_trigger = Select.ar(softSync, [soft_sync_trigger, direction]);

	// modulator_phase = ~phasorSoftSync.value(modFreq, 2 * pi, direction);
	modulator_phase = ~phasorSync.value(modFreq, 2 * pi, soft_sync_trigger, hard_sync_trigger);

	modulator_phase = Lag.ar(modulator_phase, phasorFilter);

	modulator_osc = SinOsc.ar(0, modulator_phase);
	// modulator_osc = Fold.ar(MulAdd(modulator_phase,4),-1,1);
	// modulator_osc = modulator_phase / (2 * pi) * 2 -1;

	out = modulator_osc;

	Out.ar(0, (out * 0.25) ! 2);
	// For debugging
	// Out.ar(0, [out, modulator_phase / (2 * pi)])

}).add;
)

(
SynthDef(\modularPMSyncOsc, {|freq = 120, amp = 1, out = 0, hardSyncBus = 0, softSyncBus = 0, phaseOffsetBus = 0, phaseOffsetIndex = 0, phasorLag = 0 |
    var carrier_phase, carrier_increment;
	var soft_sync_direction, hard_sync_trigger, soft_sync_in, hard_sync_in;
	var modulator_increment, modulator_osc, modulator_phase, mod_unit;
	var out;

	soft_sync_in = In.ar(softSyncBus);
	hard_sync_in = In.ar(hardSyncBus);

	hard_sync_trigger = Changed.ar(~detectDirection.value(hard_sync_in));
	soft_sync_trigger = ~detectDirection.value(soft_sync_in,[-1,1]);

	modulator_phase = ~phasorSync.value(modFreq, 2 * pi, soft_sync_trigger, hard_sync_trigger);
	modulator_osc = SinOsc.ar(0, LPF.ar(modulator_phase, 10000));
	// modulator_osc = Fold.ar(MulAdd(modulator_phase,4),-1,1);
	// modulator_osc = modulator_phase / (2 * pi) * 2 -1;

	out = modulator_osc;

	// Out.ar(0, (out * 0.25) ! 2);

}).add;
)


x = Synth(\testOscSync, ["freq": 110, "modFreq": 130, "mix": 0, "hardSync": 0, "softSync": 0]);
x.set(\freq,110*3);
x.set(\freq,220);
x.set(\modFreq,110*5/3);
x.set(\modFreq,360);
x.set(\modFreq,420);


x = Synth(\testOscSync, ["freq": 40, "modFreq": 65, "mix": 0, "hardSync": 0, "softSync": 1]);
x.set(\modFreq, 74); x.set(\freq, 40);
x.set(\phasorFilter, 0.006);
x.set(\softSync, 1);
x.set(\hardSync, 1);
x.free();

x = Synth(\pmSoftSyncPhasor, ["freq": 110, "modFreq": 120, "mix": 0]);
x = Synth(\pmSoftSyncSin, ["freq": 110, "modFreq": 120, "mix": 0]);
x.set(\mix,1)
x.set(\freq,110)
x.set(\modFreq,365)
x.set(\index,0.5)
x.free()
s.freeAll()

x = Synth(\reverseSync, ["freq": 12, "modFreq": 12, "mix": 0]);
