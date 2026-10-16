// Presets for Day, Night and events, and example events, grouped by archetype. Effects are written in the
// builder's key order, so that applying one reads like the mod's own examples.
(function (root, factory) {
    var api = factory();
    if (typeof module === "object" && module.exports) {
        module.exports = api;
    } else {
        root.CrepuscularPresets = api;
    }
})(this, function () {
    "use strict";

    // Applying a preset replaces these keys even where it doesn't list them, so nothing is left over
    // from the definition it lands on.
    var ZOMBIE_KEYS = ["speed", "steps", "health", "rise", "wake", "off"];

    // Optional mods a preset can rely on, by the kind name the mod uses for them.
    var MODS = {
        mutants: { name: "The Mutants", without: "no mutants appear, whatever off= allows" },
        cof: { name: "Cry of Fear Monster NPCs", without: "the game skips its set.COF_Spawns values with a warning, and no Cry of Fear monster appears" },
    };

    var NOTE = {
        sound: "sound= plays on each player's game as an interface sound, not in the world: zombies don't hear it, so it can't draw them.",
        mortality: "Mortality is picked when an infection starts, so a bite taken while this applies keeps its time to death after it ends; Reanimate is picked the same way, when a body dies.",
        senses: "Sight and Hearing stick: a zombie that loads in while this applies keeps its poor sight and sharp hearing after it ends, until it unloads. Only the vision radius and how far hordes hear go back at once.",
        darkness: "NightDarkness=1 takes the floor of the ambient light to 0, so ambient= goes nearly black; the moon and the Night Vision trait still lift it a little. Every player's game gets it, and a player who joins gets it as they connect.",
        transmission: "Transmission=3 is read at each wound and each death: anyone who dies while it applies turns, players too.",
        mutantRates: "The Mutants decides how many mutants it makes when the game starts: off=none lets them appear but can't make more.",
        fog: "A server whose MaxFogIntensity is below Normal caps fog=, and fogcolor= shows only with the improved fog.",
        untuned: "The sky values are a first guess: check them in the game and adjust to taste.",
        risers: "A riser is an ordinary zombie of the definition in effect, no faster than the rest. With the mod's default options a zombie that dies burning stays down, and Finish off keeps a corpse down.",
        cold: "The temperature is the one at the decision, as the night or day begins.",
    };

    var HERD = "Inspired by Night of the Living Dead, Dawn of the Dead (1978), The Walking Dead and World War Z (novel)";
    var FRENZY = "Inspired by 28 Days Later, Dawn of the Dead (2004), Train to Busan, [REC], Zombieland and DayZ";
    var HORDE = "Inspired by Left 4 Dead 2, World War Z (film) and Days Gone";
    var TOWN = "Inspired by Silent Hill and Cry of Fear";
    var LAB = "Inspired by Resident Evil";
    var HUNTERS = "Inspired by I Am Legend, Dying Light and Kingdom";
    var SPORES = "Inspired by The Last of Us";
    var GRAVE = "Inspired by Army of Darkness and Return of the Living Dead";

    var HERD_FX = "speed=-60;steps=1;health=1;rise=0;wake=false;off=mutants,cof;set.ZombieLore.ThumpNoChasing=true;set.ZombieConfig.RallyGroupSize=40;set.ZombieConfig.RallyTravelDistance=35;say=A herd is moving through. Keep the noise down.;color=b4b4a0;sound=MetaShotgun1";
    var HORDE_SETS = "off=none;set.ZombieLore.ThumpNoChasing=true;set.ZombieLore.FenceThumpersRequired=10;set.ZombieConfig.RallyGroupSize=50;set.MetaEvent=3;say=Here they come. Stay together.;color=ff9030";

    var GROUPS = [
        {
            name: "Herd",
            presets: [
                {
                    id: "herd", name: "Herd", inspiredBy: HERD,
                    blurb: "Slow dead in large groups that gather and bang on doors and walls even with no one to chase. No monsters, washed-out colour, and a far-off shot as it begins.",
                    effects: HERD_FX + ";desat=0.35", needs: [],
                    notes: ["Herds can't cross the map on their own: how far hordes follow sounds is set when the server starts.", NOTE.sound],
                },
                {
                    id: "black-and-white", name: "Black and white", inspiredBy: HERD,
                    blurb: "The herd in grey: the world loses all its colour.",
                    effects: HERD_FX + ";desat=1", needs: [],
                    notes: ["desat= fades with the daylight, so the world is grey by day only.", NOTE.sound],
                },
            ],
            examples: [
                {
                    id: "herd", name: "Herd", inspiredBy: HERD,
                    blurb: "A herd passes every 8 to 14 days after the first week, for a day and the night after it. Anyone who dies while it lasts turns.",
                    text: "id=herd;track=sun;mindays=7;interval=8d..14d;chance=60;for=2p;prio=5;speed=-60;steps=1;health=1;rise=0;wake=false;off=mutants,cof;set.ZombieLore.ThumpNoChasing=true;set.ZombieLore.Transmission=3;set.ZombieConfig.RallyGroupSize=40;set.ZombieConfig.RallyTravelDistance=35;say=A herd is moving through. Keep the noise down.;color=b4b4a0;sound=MetaShotgun1;desat=0.35",
                    needs: [], notes: [NOTE.transmission, NOTE.sound],
                },
                {
                    id: "hard-freeze", name: "Hard freeze", inspiredBy: HERD,
                    blurb: "On nights at -5 °C or colder the dead are slow and stiff: every ordinary zombie is a shambler.",
                    text: "id=hardfreeze;track=moon;tempmax=-5;prio=6;speed=-100;steps=2;health=1;rise=0;wake=false;off=mutants,cof;say=The cold has the dead slow and stiff.;color=a0c8ff",
                    needs: [], notes: [NOTE.cold],
                },
            ],
        },
        {
            name: "Frenzy",
            presets: [
                {
                    id: "frenzy", name: "Frenzy", inspiredBy: FRENZY,
                    blurb: "Sprinting, fragile infected who die like people. A bite turns within hours, and nothing gets back up.",
                    effects: "speed=+60;steps=2;health=0.8;rise=0;wake=false;off=mutants,cof;set.ZombieLore.Mortality=4;say=They are not walking any more. They are running.;color=ff5040;sound=MetaScream;desat=0.2",
                    needs: [], notes: [NOTE.mortality, NOTE.sound],
                },
                {
                    id: "double-tap", name: "Double tap", inspiredBy: FRENZY,
                    blurb: "Fast and bright, and some of the dead get up again: make sure they stay down.",
                    effects: "speed=+50;steps=2;health=0.8;rise=15;wake=true;off=mutants,cof;say=Make sure they stay down.;color=ffd040;sound=MetaPistol1;sky=ffe0a020",
                    needs: [], notes: [NOTE.risers, NOTE.sound],
                },
                {
                    id: "starving", name: "Starving", inspiredBy: FRENZY,
                    blurb: "Sprinters who waste away: their health falls from full to 40 percent between world days 28 and 84. For Day or Night, with no line of its own.",
                    effects: "speed=+60;steps=2;health=1..0.4;rise=0;wake=false;grow=28d..84d;off=mutants,cof;set.ZombieLore.Mortality=4;desat=0.2",
                    needs: [], notes: [NOTE.mortality],
                },
            ],
            examples: [
                {
                    id: "frenzy", name: "Frenzy", inspiredBy: FRENZY,
                    blurb: "Rare: from day 3, at most every 20 days, a day and the night after it of sprinters.",
                    text: "id=frenzy;track=sun;mindays=3;cooldown=20d;chance=10;for=2p;prio=20;speed=+60;steps=2;health=0.8;rise=0;wake=false;off=mutants,cof;set.ZombieLore.Mortality=4;say=They are not walking any more. They are running.;color=ff5040;sound=MetaScream;desat=0.2",
                    needs: [], notes: [NOTE.mortality, NOTE.sound],
                },
                {
                    id: "blackout", name: "Blackout", inspiredBy: FRENZY,
                    blurb: "A rare night from day 5 when the lights fail: pitch black, with sprinting infected.",
                    text: "id=blackout;track=moon;mindays=5;cooldown=15d;chance=8;prio=18;speed=+60;steps=2;health=0.8;rise=0;wake=false;off=mutants,cof;set.ZombieLore.Mortality=4;set.NightDarkness=1;say=The lights are failing. Something moves in the dark.;color=d0d0d0;sound=WorldEventElectricityShutdown;dark=1;ambient=0.05",
                    needs: [], notes: [NOTE.mortality, NOTE.darkness, NOTE.sound],
                },
            ],
        },
        {
            name: "Horde rush",
            presets: [
                {
                    id: "horde-rush", name: "Horde rush", inspiredBy: HORDE,
                    blurb: "Many fast but fragile zombies that pile against fences and gather in big groups, mutants among them, with distant gunfire often.",
                    effects: "speed=+50;steps=1;health=0.5;rise=0;wake=false;" + HORDE_SETS + ";sound=MetaAssaultRifle1",
                    needs: ["mutants"], notes: ["Only fences bend under a pile, not walls.", NOTE.mutantRates, NOTE.sound],
                },
                {
                    id: "growing-hordes", name: "Growing hordes", inspiredBy: HORDE,
                    blurb: "The horde rush, faster as the world ages: from a quarter of the zombies faster on world day 10 to 60 percent on world day 90.",
                    effects: "speed=+25..+60;steps=1;health=0.5;rise=0;wake=false;grow=10d..90d;" + HORDE_SETS + ";sound=MetaAssaultRifle1",
                    needs: ["mutants"], notes: [NOTE.mutantRates, NOTE.sound],
                },
            ],
            examples: [
                {
                    id: "horde-storm", name: "Horde storm", inspiredBy: HORDE,
                    blurb: "Stormy or rainy afternoons from day 5, at most weekly: six hours of horde rush from 14:00.",
                    text: "id=hordestorm;track=sun;mindays=5;cooldown=7d;weather=storm,rain;chance=30;at=14;for=6h;prio=15;speed=+50;steps=1;health=0.5;rise=0;wake=false;" + HORDE_SETS + ";sound=Thunder",
                    needs: ["mutants"], notes: [NOTE.mutantRates, NOTE.sound],
                },
            ],
        },
        {
            name: "Nightmare town",
            presets: [
                {
                    id: "fog-town", name: "Fog town", inspiredBy: TOWN,
                    blurb: "Thick, pale fog and slow zombies; Cry of Fear monsters at their highest are the threat. Best by day.",
                    effects: "speed=-50;steps=1;health=1;rise=0;wake=false;off=none;set.COF_Spawns.Regular=5;say=The fog is so thick you can barely see the street.;color=c8c8c8;sound=RadioZap;fogcolor=d0d0c8;fog=0.8;desat=0.5",
                    needs: ["cof"], notes: [NOTE.fog, NOTE.sound, NOTE.untuned],
                },
                {
                    id: "nightmare", name: "Nightmare", inspiredBy: TOWN,
                    blurb: "Near-black, rust-red light, a thin dark fog and Cry of Fear monsters at their highest. Best by night.",
                    effects: "speed=-50;steps=1;health=1.2;rise=0;wake=false;off=none;set.COF_Spawns.Regular=5;set.NightDarkness=1;say=A siren wails somewhere. The town is changing.;color=b03028;sound=ZombieSurprisedPlayer;sky=5a2a2a60;fogcolor=4a2a24;fog=0.3;dark=1;ambient=0.05",
                    needs: ["cof"], notes: [NOTE.darkness, "No siren in the game plays only once, so the siren is in the line.", NOTE.sound, NOTE.untuned],
                },
            ],
            examples: [
                {
                    id: "fog-town-nightmare", name: "Fog town, then the nightmare", inspiredBy: TOWN,
                    blurb: "A foggy day becomes Fog town, at most every 14 days, and the night after it may turn into the Nightmare. Both are added, the second chained after the first.",
                    text: "id=fogtown;track=sun;cooldown=14d;weather=fog;chance=50;prio=15;speed=-50;steps=1;health=1;rise=0;wake=false;off=none;set.COF_Spawns.Regular=5;say=The fog is so thick you can barely see the street.;color=c8c8c8;sound=RadioZap;fogcolor=d0d0c8;fog=0.8;desat=0.5"
                        + "|id=nightmare;track=moon;after=fogtown;chance=60;prio=30;speed=-50;steps=1;health=1.2;rise=0;wake=false;off=none;set.COF_Spawns.Regular=5;set.NightDarkness=1;say=A siren wails somewhere. The town is changing.;color=b03028;sound=ZombieSurprisedPlayer;sky=5a2a2a60;fogcolor=4a2a24;fog=0.3;dark=1;ambient=0.05",
                    needs: ["cof"], notes: ["Without natural fog, give fogtown season=autumn;chance=10 instead of weather=fog;chance=50.", NOTE.darkness, NOTE.sound, NOTE.untuned],
                },
            ],
        },
        {
            name: "Lab leak",
            presets: [
                {
                    id: "lab-leak", name: "Lab leak", inspiredBy: LAB,
                    blurb: "Slow, tough dead with mutants among them, and a third of the kills get back up unless burned or finished off. Thunder as it begins.",
                    effects: "speed=-40;steps=1;health=1.6;rise=35;wake=true;off=cof;say=Lightning shows shapes on the lawn. Burn what you put down.;color=8cb478;sound=Thunder;sky=8cb48c30;desat=0.15",
                    needs: ["mutants"], notes: [NOTE.risers, NOTE.mutantRates, NOTE.sound],
                },
            ],
            examples: [
                {
                    id: "lab-leak", name: "Lab leak", inspiredBy: LAB,
                    blurb: "Stormy or rainy nights from day 10, at most every 10 days.",
                    text: "id=lableak;track=moon;mindays=10;cooldown=10d;weather=storm,rain;chance=35;prio=12;speed=-40;steps=1;health=1.6;rise=35;wake=true;off=cof;say=Lightning shows shapes on the lawn. Burn what you put down.;color=8cb478;sound=Thunder;sky=8cb48c30;desat=0.15",
                    needs: ["mutants"], notes: [NOTE.risers, NOTE.mutantRates, NOTE.sound],
                },
            ],
        },
        {
            name: "Night hunters",
            presets: [
                {
                    id: "sun-weakened", name: "Sun-weakened", inspiredBy: HUNTERS,
                    blurb: "Every ordinary zombie a tier slower and fragile, those already around too. For Day, with Night hunters for Night.",
                    effects: "speed=-100;steps=1;health=0.5;rise=0;wake=false;off=mutants,cof;say=Daylight. They are hiding from the sun.;color=ffe6a0",
                    needs: [], notes: ["health=0.5 also lowers the zombies already around, and a lowered zombie never heals, so the days wear them down."],
                },
                {
                    id: "night-hunters", name: "Night hunters", inspiredBy: HUNTERS,
                    blurb: "Half of the zombies sprint, the ones that come in are tougher, and the night is pitch black. For Night, with Sun-weakened for Day.",
                    effects: "speed=+50;steps=2;health=1.3;rise=0;wake=false;off=none;set.NightDarkness=1;say=Night falls. Get inside.;color=8080ff;sound=MetaScream;dark=1;ambient=0.05",
                    needs: [], notes: [NOTE.darkness, NOTE.sound],
                },
            ],
            examples: [
                {
                    id: "moonless", name: "Moonless", inspiredBy: HUNTERS,
                    blurb: "New-moon nights are worse: faster, tougher and darker still.",
                    text: "id=moonless;track=moon;moon=new;chance=50;prio=12;speed=+75;steps=2;health=1.5;rise=0;wake=false;off=none;set.NightDarkness=1;say=No moon tonight. They hunt in the dark.;color=6060c0;sound=MetaScream;dark=1;ambient=0.03",
                    needs: [], notes: [NOTE.darkness, NOTE.sound],
                },
                {
                    id: "cold-snap", name: "Cold snap", inspiredBy: HUNTERS,
                    blurb: "On a day at 5 °C or colder, at most every 3 days, they don't sleep: as fast and tough as Night hunters.",
                    text: "id=coldsnap;track=sun;cooldown=3d;tempmax=5;chance=50;prio=11;speed=+50;steps=2;health=1.3;rise=0;wake=false;off=none;say=It is cold enough that they do not sleep today.;color=a0d0ff",
                    needs: [], notes: [NOTE.cold],
                },
            ],
        },
        {
            name: "Spore bloom",
            presets: [
                {
                    id: "spore-bloom", name: "Spore bloom", inspiredBy: SPORES,
                    blurb: "Zombies that see poorly but hear everything, a third of them faster and all tougher, in a yellow haze. Sneaking works; gunfire doesn't.",
                    effects: "speed=+30;steps=1;health=1.3;rise=0;wake=false;off=cof;set.ZombieLore.Sight=3;set.ZombieLore.Hearing=1;say=The air is thick with spores. Move quietly.;color=c8c070;sky=d8cc9030;fogcolor=c8c48c;fog=0.35;desat=0.25",
                    needs: [], notes: [NOTE.senses, "The haze is only a look: nothing spreads through the air, and zombies never see less than 10 tiles.", NOTE.untuned],
                },
            ],
            examples: [
                {
                    id: "spore-bloom", name: "Spore bloom", inspiredBy: SPORES,
                    blurb: "Foggy or rainy days from June to October, from day 14 and at most every 15 days: three days of spore bloom.",
                    text: "id=sporebloom;track=sun;month=6..10;mindays=14;cooldown=15d;weather=fog,rain;chance=25;for=3d;prio=14;speed=+30;steps=1;health=1.3;rise=0;wake=false;off=cof;set.ZombieLore.Sight=3;set.ZombieLore.Hearing=1;say=The air is thick with spores. Move quietly.;color=c8c070;sky=d8cc9030;fogcolor=c8c48c;fog=0.35;desat=0.25",
                    needs: [], notes: [NOTE.senses, NOTE.untuned],
                },
            ],
        },
        {
            name: "Grave rise",
            presets: [
                {
                    id: "grave-rise", name: "Grave rise", inspiredBy: GRAVE,
                    blurb: "Most of the dead get back up, tougher, and bang on doors and walls under a pale mist. Only fire or Finish off keeps them down.",
                    effects: "speed=+25;steps=1;health=1.4;rise=80;wake=true;off=mutants;set.ZombieLore.ThumpNoChasing=true;say=The dead will not stay down tonight.;color=90c890;sound=MetaWolfHowl;sky=7890c050;fogcolor=a8b8a8;fog=0.3",
                    needs: [], notes: ["Only zombies killed while it applies get up: no corpse climbs out of the ground. Rises per body limits how often one body gets up.", NOTE.sound],
                },
            ],
            examples: [
                {
                    id: "grave-rise", name: "Grave rise", inspiredBy: GRAVE,
                    blurb: "Some full moons from day 14, at most every 20 days; it beats the blood moon when it rolls.",
                    text: "id=graverise;track=moon;moon=full;mindays=14;cooldown=20d;chance=25;prio=25;speed=+25;steps=1;health=1.4;rise=80;wake=true;off=mutants;set.ZombieLore.ThumpNoChasing=true;say=The dead will not stay down tonight.;color=90c890;sound=MetaWolfHowl;sky=7890c050;fogcolor=a8b8a8;fog=0.3",
                    needs: [], notes: [NOTE.risers, NOTE.sound],
                },
                {
                    id: "black-rain", name: "Black rain", inspiredBy: GRAVE,
                    blurb: "Rainy nights from day 14, at most every 10 days: fast dead, and most of them get back up.",
                    text: "id=blackrain;track=moon;mindays=14;cooldown=10d;weather=rain,storm;chance=15;prio=24;speed=+50;steps=2;health=1.4;rise=80;wake=true;off=mutants;say=The rain smells of chemicals. Burn the dead.;color=a0a070;sound=RumbleThunder",
                    needs: [], notes: [NOTE.risers, NOTE.sound],
                },
            ],
        },
        {
            name: "More moons and suns",
            presets: [],
            examples: [
                {
                    id: "blue-moon", name: "Blue moon", inspiredBy: null,
                    blurb: "Every 4th full moon: the dead are slow, but every one killed gets back up, under a blue light.",
                    text: "id=bluemoon;track=moon;moon=full;nth=4;prio=20;speed=-100;health=1.5;rise=100;wake=true;say=A pale blue moon. The dead are slow but will not stay down.;color=6496ff;sky=5a78c8a0",
                    needs: [], notes: [],
                },
                {
                    id: "green-moon", name: "Green moon", inspiredBy: null,
                    blurb: "One new moon in ten: a sickly green fog, and Cry of Fear monsters at their highest.",
                    text: "id=greenmoon;track=moon;moon=new;chance=10;off=none;set.COF_Spawns.Regular=5;say=A sickly green glow hangs over the town.;color=78dc78;fogcolor=a0d2a0;fog=0.4",
                    needs: ["cof"], notes: [],
                },
                {
                    id: "red-sun-long-night", name: "Red sun and the long night after it", inspiredBy: null,
                    blurb: "On 15 percent of summer days every ordinary zombie sprints, and half the time the night after lasts three and a half days. Both are added, the long night chained after the red sun.",
                    text: "id=redsun;track=sun;season=summer;chance=15;speed=+100;steps=2;health=0.5;say=The sun burns red. They are fast today.;color=ff7832;sky=ff9664a0"
                        + "|id=longnight;track=moon;after=redsun;chance=50;for=3.5d;prio=50;speed=-100;rise=100;wake=true;off=mutants;say=The night does not end.;color=8080a0;fog=0.3;dark=1;ambient=0.15",
                    needs: [], notes: [],
                },
                {
                    id: "eclipse", name: "Eclipse", inspiredBy: null,
                    blurb: "About once a year, on a new moon: two dark hours from noon, and the dead get back up.",
                    text: "id=eclipse;track=sun;moon=new;nth=12;at=12;for=2h;prio=30;speed=-50;rise=100;wake=true;off=none;say=The sun goes dark.;color=c8c8c8;sky=202030ff",
                    needs: [], notes: ["With fixed hours, at=12 must fall in the day: a night that takes in noon makes it an error."],
                },
                {
                    id: "halloween", name: "Halloween", inspiredBy: null,
                    blurb: "Every 31 October, above everything else: every kill gets back up, monsters are out, and an orange glow.",
                    text: "id=halloween;track=moon;date=10-31;prio=40;rise=100;wake=true;off=none;set.COF_Spawns.Regular=5;say=Happy Halloween.;color=ff8c00;sky=ff8c0060",
                    needs: ["cof"], notes: [],
                },
                {
                    id: "bright-moon", name: "Bright moon every 30 days", inspiredBy: null,
                    blurb: "Every 30 days from world day 30: a line, nothing else. It counts world days, not the moon.",
                    text: "id=fullmoon;track=moon;every=30;mindays=30;say=The moon is bright tonight.;color=e6e6ff",
                    needs: [], notes: [],
                },
            ],
        },
    ];

    return { ZOMBIE_KEYS: ZOMBIE_KEYS, MODS: MODS, GROUPS: GROUPS };
});
