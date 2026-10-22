# Crepuscular

**Action by day. Horror by night.**

A Project Zomboid Build 42 mod that gives day and night their own rules: faster, more fragile zombies in daylight, slower dead that get back up after dark (with [Relentless Dead](#risers)), and special moons and suns in between.

> **In testing:** expect bugs, and settings may still change between updates. Please report problems on [GitHub](https://github.com/zexyqag/Crepuscular/issues).

- **Steam Workshop:** [Crepuscular (testing)](https://steamcommunity.com/sharedfiles/filedetails/?id=3820511464)
- **Builder:** [zexyqag.github.io/Crepuscular/builder](https://zexyqag.github.io/Crepuscular/builder/), which writes the settings for you
- **Issues:** [github.com/zexyqag/Crepuscular/issues](https://github.com/zexyqag/Crepuscular/issues)
- **Workshop ID:** `3820511464`
- **Mod ID:** `Crepuscular`
- **Game:** Build 42.20.2 or later, single player and multiplayer

## Contents

- [What it does](#what-it-does)
  - [The defaults](#the-defaults)
- [Getting started](#getting-started)
- [How it works](#how-it-works)
- [Definition reference](#definition-reference)
- [Events reference](#events-reference)
- [Risers](#risers)
- [Sky and fog](#sky-and-fog)
- [Monster mods and kinds](#monster-mods-and-kinds)
- [Presets and examples](#presets-and-examples)
- [All sandbox options](#all-sandbox-options)
- [Admin menu and Status](#admin-menu-and-status)
- [Multiplayer and performance](#multiplayer-and-performance)
- [For modders](#for-modders)
- [Compatibility](#compatibility)
- [Known limitations](#known-limitations)
- [Not yet verified in game](#not-yet-verified-in-game)
- [Reporting problems](#reporting-problems)
- [Publishing](#publishing)

## What it does

Crepuscular splits the game's clock into day and night and gives each one a **definition**: a short line of `key=value` fields. A definition says:

- how many zombies are faster or slower, and how tough they are;
- how many of the zombies killed while it applies get back up, and whether they may get up now (with Relentless Dead, see [Risers](#risers));
- which sandbox options change while it lasts;
- the sky colour, fog and darkness;
- which monsters are about: The Mutants, Cry of Fear and Silent Hill stop making monsters, Blackout Predators stops turning zombies into Volatiles, and other monster mods' far monsters are removed (see [Monster mods and kinds](#monster-mods-and-kinds));
- a line players see, and a sound they hear, when it begins.

**Events** are special nights and days (moons and suns) with conditions of their own: moon phase, date, season, weather, every few days, after another event, at random. While an event runs, its definition takes over from Day or Night.

**It works as soon as it is enabled, with no setup.** The defaults below apply without any configuration. Crepuscular needs no other mod: its parts for [Relentless Dead](https://steamcommunity.com/sharedfiles/filedetails/?id=3824839394), [The Mutants](https://steamcommunity.com/sharedfiles/filedetails/?id=3796669056), [Cry of Fear Monster NPCs](https://steamcommunity.com/sharedfiles/filedetails/?id=3813406470), [Silent Hill Monster NPCs](https://steamcommunity.com/sharedfiles/filedetails/?id=3821752171), [Blackout Predators](https://steamcommunity.com/sharedfiles/filedetails/?id=3766513120) and [Zomboid Forge](https://steamcommunity.com/sharedfiles/filedetails/?id=3776274080) apply only when those mods are installed, and without them the same settings have nothing to act on. Killed zombies get back up only with Relentless Dead installed.

### The defaults

```
Day      speed=+25;health=0.7
Night    speed=-50;rise=50;wake=true;off=mutants
Events1  id=bloodmoon;track=moon;moon=full;chance=50;prio=10;speed=+50;rise=100;wake=true;off=none;say=@IGUI_Crepuscular_BloodMoon;color=ff3c3c
```

| When | What happens |
|---|---|
| Day | A quarter of the ordinary zombies are one speed tier faster (with the game's default speed, fast shamblers become sprinters). New and reloaded zombies get 70% of the health they roll, and no ordinary zombie keeps more than 70% of the most a new one can have. Zombies killed by day stay down. |
| Night (20:00 to 04:00) | Half of the ordinary zombies are one tier slower. With Relentless Dead, half of the zombies killed at night are marked to get back up (unless something keeps it down) 1 to 2 in-game hours later; they get up only at night, so a kill just before dawn waits for the next night. If The Mutants is installed, it makes no new mutants at night and far mutants are removed. If Blackout Predators is installed, its Volatiles hunt from Crepuscular's dusk to its dawn, and sleep in their nests by day. |
| Blood moon | On the first night of each full moon, a 50% chance. Half of the ordinary zombies are one tier faster, with Relentless Dead every zombie killed that night is marked to get back up (unless something keeps it down), The Mutants (if installed) may make mutants, and every player sees "The moon rises red. A blood moon has begun." in red. |

The sky is the game's own unless a definition sets it.

## Getting started

### Single player

1. Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3820511464).
2. Enable **Crepuscular** in the game's Mods screen.
3. Start a game. The defaults apply. To change them, open the **Crepuscular** page of the sandbox settings.

In single player you also get the [admin menu](#admin-menu-and-status).

### Dedicated server

In the server's settings file, `Zomboid/Server/<servername>.ini`, add the Workshop item and the mod id (add them to any existing lists with `;`):

```ini
WorkshopItems=3820511464
Mods=Crepuscular
```

You may see Build 42 mod ids written with a leading backslash, as in `Mods=\Crepuscular`. The 42.20.2 server removes every backslash from `Mods=` before it reads the list, so `Crepuscular` and `\Crepuscular` both load the mod. `3820511464\Crepuscular` does not.

Players get the mod from the Workshop when they join, as with any Workshop item. The server's options apply to everyone.

### Where the options are

- **New game or hosted game:** the **Crepuscular** page of the sandbox settings.
- **Dedicated server:** `Zomboid/Server/<servername>_SandboxVars.lua`, in the `Crepuscular = { ... }` table. Edit it while the server is stopped.
- **Names:** each option is `Crepuscular.<Name>`, for example `SandboxVars.Crepuscular.Night`. See [All sandbox options](#all-sandbox-options).
- **While the game runs:** the definitions are parsed again whenever their text changes, within an in-game minute.
- **Size:** keep each text option under 32000 bytes. The game stores a text option behind a 16-bit length, and above 32767 bytes it silently corrupts the save and the connect packet. Status shows each option's size.

### The builder

The [builder](https://zexyqag.github.io/Crepuscular/builder/) is a page that writes Day, Night, the events and the kinds through forms, and checks them with the mod's own rules. It runs entirely in your browser and sends nothing anywhere; your work is kept in that browser.

| Tab | What it does |
|---|---|
| Definitions | Forms for Day, Night and each event, with [presets and example events](#presets-and-examples), ready lines for known monster mods, and the errors and warnings the mod would log. |
| Calendar | A simulated calendar of which events would run, with statistics over many simulated years. Chances and weather are rolled, and the season is approximate. |
| Import | Paste one option's text, a `SandboxVars.lua` file or its `Crepuscular = { ... }` table, or `SANDBOX_Crepuscular__` lines of an env file. |
| Export | The texts to paste into the sandbox settings, the lines for `SandboxVars.lua`, and env lines for server images that take `SANDBOX_` variables. |

## How it works

### The clock

| Night mode | Night is |
|---|---|
| Fixed hours (default) | From `NightStartHour`:00 to `NightEndHour`:00, 20:00 to 04:00 by default, every day of the year, whatever the game's Day/Night Cycle setting. Night may run past midnight. If both hours are the same there is no night at all, and the log says so. |
| Seasonal night | The game's own dusk and dawn, which move with the seasons and follow the Day/Night Cycle setting: endless day has no night, endless night is always night. |

The clock only decides which definition applies. It doesn't change the game's time or light; for that, see [Sky and fog](#sky-and-fog).

### Occasions: decided once

Each night and each day is an **occasion**. A night belongs to the date it began on.

- When an occasion begins, the server decides once whether an event runs in it, and keeps that decision in the save. A restart or a reload never rolls again.
- **World days** are the days since the world began, counted at noon of the occasion's date. `mindays=`, `maxdays=`, `every=`, `interval=` in days and `grow=` count them.
- The admin menu's **Re-decide this occasion** rolls again on purpose.

### Definitions: Day, Night and events

- **Day** applies by day and **Night** by night, while no event runs.
- An **event** has a track. A `track=moon` event is decided when night begins; a `track=sun` event when day begins.
- **An event layers on its phase.** A moon event starts from Night and a sun event from Day: every key it doesn't set keeps its base's value, except `say=`, `color=` and `sound=`, which belong only to the definition that sets them.
  - `set.` entries add to the base's; the event's own win for the same option.
  - `off=` replaces the base's list when the event has one.
  - A range it takes from its base grows with the base's `grow=`.
- An event keeps its base for as long as it runs: a moon event that runs into the day still builds on Night, not Day.
- When an event ends, Day or Night applies again. The phase's own line isn't shown again.

### One event at a time

- **One event runs at a time.** While it runs, nothing else is decided: an occasion that begins during it is covered by it.
- **Priorities:** when several events qualify, they are tried from the highest `prio=` down. Between equal priorities, the earlier option goes first (Events1 before Events2), then the earlier event in the option. Each one's `chance=` is rolled in turn, and the first that passes runs.
- When an event ends in the middle of an occasion, no other event starts in that occasion, unless an admin starts or re-decides one.

## Definition reference

### Syntax

- Fields are `key=value`, separated by `;`. In the Events options, events are separated by `|`.
- Spaces around keys, values and separators don't matter. A line break or tab inside a field is an error.
- Keys and values don't depend on upper or lower case, except `say=` and `sound=`, and the names and values of `set.` entries, which are kept as written.
- Each key may appear once per definition.
- **Errors:** in Day and Night a bad field is skipped and logged, and the rest applies. An event with an error is skipped whole and logged. Admins see a line about definitions with errors when they join, and Status lists every error and warning.

### Effect keys

Day, Night and events can all have these.

| Key | Values | Meaning |
|---|---|---|
| `speed` | Whole number, -100 to 100, or a [range](#growth) | `+N`: N percent of the ordinary zombies are one tier faster (shambler to fast shambler, fast shambler to sprinter). `-N`: N percent are one tier slower. `0`: the game's own speeds. `speed=25` means `+25`. |
| `steps` | 1 or 2 (default 1) | Tiers moved. `steps=2` makes them always sprinters or always shamblers. |
| `health` | 0.1 to 5, or a range (default 1) | Below 1: new and reloaded zombies get that share of the health they roll, and any ordinary zombie above that share of the most a new one can have is lowered to it. Above 1: new and reloaded zombies get that much more, and zombies already around keep theirs. A zombie is never healed. |
| `rise` | Whole number, 0 to 100, or a range (default 0) | Percent of the zombies killed while this applies that are marked to get back up, with Relentless Dead. See [Risers](#risers). |
| `wake` | `true` or `false` (default false) | Marked corpses may get up while this applies, with Relentless Dead. |
| `off` | `none`, or kind names separated by `,` | The [monster kinds](#monster-mods-and-kinds) that are off while this applies. Default: none off. |
| `grow` | `Nd` or `Ad..Bd` | Moves this definition's ranges with the world days. See [Growth](#growth). |
| `set.Table.Option` or `set.Option` | The option's value | Changes a sandbox option while this applies. See [Sandbox values](#sandbox-values-set). |
| `say` | Text, or `@Key` for a translation | A line every player sees when it begins. |
| `color` | `rrggbb` (default `ffffff`) | The line's colour. |
| `sound` | A game sound name | A sound every player hears when it begins. Upper and lower case matter. |
| `sky`, `fogcolor`, `fog`, `desat`, `dark`, `ambient` | See [Sky and fog](#sky-and-fog) | The sky colour, fog and darkness. |

**Speed in detail:**

- The same zombies are picked on the server and on every player's game, from each zombie's persistent outfit ID, so a reloaded zombie keeps its place. A zombie that speeds up is among the last to slow down.
- The base tier is the game's `ZombieLore.Speed`. With Random, `SprinterPercentage` of the zombies are sprinters and the rest are split between fast shamblers and shamblers, fixed per zombie.
- Each in-game minute every game checks up to `ZombiesPerSweep` zombies. After a change it takes about the number of loaded zombies divided by that many minutes until every zombie has it.
- The log warns when `ZombieLore.Speed` is Sprinters (the game makes every zombie run when it lunges, so `speed=-N` can't slow them) and when `ZombieLore.ActiveOnly` isn't Both (the game itself turns inactive zombies into shamblers and back, which fights `speed=`).

**Who is ordinary:** speed and health change only ordinary zombies. Monsters of every kind, Bandits and crawlers keep their own speed and are never capped; the health factor is given as the game creates a zombie, before it marks some of them, so a reloaded crawler or a new mutant may get it too. Zombies playing dead and corpses being dragged are left alone.

**Health in detail:** the most a new zombie can have depends on the game's `ZombieLore.Toughness`: 3.8 for Tough and Random, 1.8 for Normal, 0.8 for Fragile. With `health=0.7` and Normal toughness, no ordinary zombie keeps more than 1.26.

### Growth

`speed`, `health`, `rise`, `fog`, `desat`, `dark` and `ambient` can be a range `A..B`, which `grow=` in the same definition moves along the world days.

| Written | Value |
|---|---|
| `speed=+25..+75;grow=60d` | +25 on world day 0, rising every day to +75 on world day 60, and +75 after. |
| `speed=+25..+75;grow=30d..90d` | +25 until world day 30, then rising to +75 on world day 90. |
| `health=0.7..0.4`, `rise=25..100`, `fog=0.2..0.6` | The same, with `grow=`. |

- Growth is linear and moves every world day: `speed=+25..+75;grow=60d` in Day goes from a quarter of the zombies faster to three quarters over the first 60 days, and `health=1..2;grow=100d` in Night makes nights that get a little tougher every day.
- Speed and rise shares are rounded to a whole percent.
- A range needs `grow=` in the same definition. Without it the range is an error and is dropped. A `grow=` with no range changes nothing, and the log warns.
- An event's `grow=` moves only its own ranges. A range it takes from Day or Night grows with their `grow=`.

### Sandbox values (set.)

`set.Table.Option=value` changes a sandbox option while the definition applies, for example `set.ZombieLore.Toughness=1`. For an option without a table, write `set.Option=value`, for example `set.HoursForCorpseRemoval=24`.

- The value is set on the server and on every player's game, and goes back to its base value when the definition ends.
- The base is the option's value before Crepuscular changed it. A change someone else makes, such as an admin or an edit of the server's sandbox file while it was stopped, becomes the new base. A save made while a definition applies gets its base back when that definition ends.
- Names and values are checked when the definitions load. An option the game doesn't have (for example one of a mod that isn't loaded), or a value it can't take, is skipped with a warning. Crepuscular's own options can't be set.
- Values: `true` or `false` for an on/off option, a number within the option's range for the others (a whole number for a choice or a whole-number option).
- While `cof` or `silenthill` is off and its mod is loaded, Crepuscular's own values for that mod win over `set.` entries for the same options.

**When a change takes effect.** Setting an option only stores the new value; it works when the game next reads it. From reading the 42.20.2 game code:

| How the game reads it | Examples | What a `set.` does |
|---|---|---|
| Where it is used | `ZombieLore.Transmission`, `ThumpNoChasing`, `ThumpOnConstruction`, `FenceThumpersRequired`, `DisableFakeDead`, `ZombieConfig.RallyGroupSize` and the other Rally options, `NightDarkness`, `MetaEvent` (its gunfire is rolled each day) | Applies at once and goes back at once. |
| When something happens | `ZombieLore.Mortality` (when an infection starts), `ZombieLore.Reanimate` (when a body dies) | Sticks to that infection or body after the definition ends. |
| Copied onto each zombie when it is created or loaded | `ZombieLore.Sight`, `Hearing`, `Strength`, `Cognition`, `Toughness`, `Speed`, `SprinterPercentage` | Only zombies created or loaded while it applies get it, and they keep it until they unload. Sight and Hearing also act partly at once. |
| At start only | Population, respawn and redistribute options, `FollowSoundDistance`, `Helicopter`, `ChanceOfAttachedWeapon` | Nothing until a restart. An admin's `/reloadoptions` during the definition keeps its population values until the next restart or reload. |

Avoid `ZombieLore.Speed`, `SprinterPercentage` and `ActiveOnly` (they fight `speed=`), `Toughness` (use `health=`), and `ZombieLore.Mortality=1`, which kills every infected player at once.

### Lines and sounds

- `say=text` shows a line to every player when the definition begins, and `say=@Key` shows that translation. `color=rrggbb` gives its colour.
- **Where:** the **Where lines show** option (`NotificationPlace`) shows the line over each player's head (the default), in chat or both. In chat it goes to the tab the player has open, as the game's server messages do, in its colour and led by `[World]`. Single player has no chat, so there it shows over the head, and the log says so once.
- `sound=Name` plays that game sound once on every player's game at the same moment, with or without a line. Names the presets use: `MetaWolfHowl`, `MetaScream`, `MetaShotgun1`, `MetaPistol1`, `MetaAssaultRifle1`, `Thunder`, `RumbleThunder`, `RadioZap`, `ZombieSurprisedPlayer`, `WorldEventElectricityShutdown`. A name the game doesn't know is a warning in the log, and players may hear nothing.
- **`sound=` is not a world sound:** it plays on each player's game as an interface sound. Zombies don't hear it, so it can't draw them.
- **When:** Day or Night when its phase begins, an event when it starts. A player who joins or loads the game while it lasts gets the line and the sound then. A forced phase shows no line.
- The **Notifications** option turns every line and sound off on every player's game; the events still run.

## Events reference

Events go into the options Events 1 to Events 8, any number in each, separated by `|`. Each event has the [effect keys](#effect-keys) plus the keys below.

### Required keys

| Key | Values | Meaning |
|---|---|---|
| `id` | a-z, 0-9 and `_` | The event's name. The first otherwise valid event with an id holds it; another with the same id is an error. |
| `track` | `moon` or `sun` | `moon`: decided when night begins, starts from Night. `sun`: decided when day begins, starts from Day. |

### Conditions

Every condition that is set must hold. Inside one condition a list such as `moon=full,new` holds when any item does. An event with no conditions can happen every night (or day), and the log warns.

| Key | Example | Holds when |
|---|---|---|
| `moon` | `moon=full` | The occasion's date is the first day of that moon phase, so `moon=full` on a moon event is the first night of a full moon. Phases: `new`, `waxingcrescent`, `firstquarter`, `waxinggibbous`, `full`, `waninggibbous`, `thirdquarter`, `waningcrescent`, or 0 to 7 (4 is full). Computed from the date with the game's own formula. |
| `date` | `date=10-31`, `date=12-20..01-05` | The date is that day or in that range. A range may run over the new year. |
| `month` | `month=6..8`, `month=11..2` | The month, 1 to 12, or a range of them, which may run over the new year. |
| `season` | `season=summer` | The game's season: `spring`, `summer`, `autumn` or `winter`. |
| `every` | `every=30`, `every=30+5` | The world day is a multiple of N (2 to 3650), or with `+K` K days after one (K below N). |
| `nth` | `nth=4`, `nth=4+1` | Every Nth time its calendar conditions hold: the 4th, 8th and so on, or with `+K` the Kth, K+Nth and so on (N 1 to 1000, K 1 to N). |
| `mindays`, `maxdays` | `mindays=30;maxdays=365` | The world day is at least, or at most, this (0 to 36500). |
| `after` | `after=redsun` | The first occasion of its track after one of these events ended. See [Chains](#chains). |
| `cooldown` | `cooldown=20d`, `cooldown=36h` | At least this long since its last start. See [Cooldown and interval](#cooldown-and-interval). |
| `interval` | `interval=3d..7d`, `interval=7d`, `interval=12h..36h` | A random wait after each start. See [Cooldown and interval](#cooldown-and-interval). |
| `weather` | `weather=rain,storm` | `rain`, `snow`, `storm`, `fog` or `clear`, as the occasion begins. Fog counts as players see it, so the `fog=` in effect counts. `clear` is none of the others. |
| `tempmin`, `tempmax` | `tempmax=-5` | The temperature in degrees C, -80 to 80, as the occasion begins. |
| `chance` | `chance=50` | Rolled once, 0 to 100. `chance=0` never happens, and the log warns. |

- The **calendar conditions** are `moon`, `date`, `month`, `season`, `every`, `mindays` and `maxdays`. `nth` counts the occasions where they all hold, including one covered by a running event.
- Weather, temperature and chance are checked at the decision, as the night or day begins, even for an event that starts later with `at=`.

### Timing

| Key | Values | Meaning |
|---|---|---|
| `at` | `HH` or `HH:MM` | Starts later in its night or day, at that time. With fixed hours it must fall inside its track's window (for a moon, 20:00 to 04:00 by default), or it is an error. If its night or day ends first, it is missed. |
| `for` | `phase` (default) | Until its night or day ends. |
| | `2p` (1 to 60 phases) | That many phases: `for=2p` on a moon event is the night and the day after it. |
| | `6h`, `3.5d` | That many hours or days, up to 30 days. If that time is over before it can start, it is missed. |
| `prio` | Whole number, -999 to 999 (default 0) | When several events qualify, the highest is tried first. |

### Chains

`after=id` (or `after=a,b`) makes an event a candidate on the first occasion of its own track after one of those events ended.

- It gets one chance: if it isn't picked then (its chance fails, it is cooling down, or another event wins), the chain is gone.
- The log warns when another event on the same track can win over it (a higher priority, or the same priority and earlier), naming each one.
- An `after=` with an id no loaded event has is an error, which skips the event.
- Status shows the chain flags that are waiting.

### Cooldown and interval

| Key | Meaning |
|---|---|
| `cooldown=20d` or `36h` | At least this long between its last start and when it would start. Longer than 0 and up to 3650 days. |
| `interval=3d..7d` | After each start it waits a random 3 to 7 whole days, counted in world days, before it can happen again. The first wait counts from world day 0. |
| `interval=7d` | Exactly 7 days. |
| `interval=12h..36h` | Whole hours from its start time; the first wait counts from 07:00 of the world's first day. Hours drift against a seasonal dusk or dawn, so days suit a nightly or daily rhythm. |

- The wait is rolled when first needed and kept until the event starts again. Once the wait is over it stays a candidate until it starts, so a lost chance or a higher priority doesn't roll a new wait.
- An admin start counts as a start for both.
- Status shows each event's last start, its cooldown and when its interval is due.

### Worked examples

**The default blood moon:**

```
id=bloodmoon;track=moon;moon=full;chance=50;prio=10;speed=+50;rise=100;wake=true;off=none;say=@IGUI_Crepuscular_BloodMoon;color=ff3c3c
```

A night event on the first night of each full moon, half the time. Priority 10 beats events without a `prio=`. Half of the ordinary zombies are one tier faster, every zombie killed is marked to rise (as far as Relentless Dead's rules allow) and may get up that night, no kind is off (so mutants are allowed), and the translated line shows in red. Everything else comes from Night.

**Halloween, every year, above everything else:**

```
id=halloween;track=moon;date=10-31;prio=40;rise=100;wake=true;off=none;say=Happy Halloween.;color=ff8c00;sky=ff8c0060
```

**A herd every 8 to 14 days after the first week, for a day and the night after it:**

```
id=herd;track=sun;mindays=7;interval=8d..14d;chance=60;for=2p;prio=5;speed=-60;steps=1;rise=0;set.ZombieLore.ThumpNoChasing=true;set.ZombieConfig.RallyGroupSize=40;say=A herd is moving through. Keep the noise down.;color=b4b4a0;desat=0.35
```

The interval is rolled after each start, and a lost 60% roll waits for the next day without rolling a new interval.

**A cold snap on freezing nights:**

```
id=hardfreeze;track=moon;tempmax=-5;prio=6;speed=-100;steps=2;say=The cold has the dead slow and stiff.;color=a0c8ff
```

`speed=-100;steps=2` makes every ordinary zombie a shambler. The temperature is the one as the night begins.

**A red sun, then perhaps a night that lasts three and a half days:**

```
id=redsun;track=sun;season=summer;chance=15;speed=+100;steps=2;health=0.5;say=The sun burns red. They are fast today.;color=ff7832;sky=ff9664a0|id=longnight;track=moon;after=redsun;chance=50;for=3.5d;prio=50;speed=-100;rise=100;wake=true;off=mutants;say=The night does not end.;color=8080a0;fog=0.3;dark=1;ambient=0.15
```

`longnight` is a candidate only on the night right after a red sun ends. It keeps Night as its base for all three and a half days, and no day is decided while it runs.

**An eclipse about once a year:**

```
id=eclipse;track=sun;moon=new;nth=12;at=12;for=2h;speed=-50;rise=100;wake=true;say=The sun goes dark.;color=c8c8c8;sky=202030ff
```

On every 12th new-moon day, two hours from noon. With fixed hours, `at=12` must fall in the day.

**Faster nights as the world ages:**

```
Night: speed=-50..+50;grow=0d..120d;rise=50;wake=true;off=mutants
```

From half of the zombies slower on world day 0 to half of them faster on world day 120. A blood moon still takes its own `speed=+50`.

**Cry of Fear monsters only at night** (with Cry of Fear Monster NPCs installed):

```
Day: speed=+25;health=0.7;off=cof
```

Keep Cry of Fear's own Night only option off; the log warns if it is on.

**Silent Hill monsters at night and in fog** (with Silent Hill Monster NPCs installed):

```
Day: speed=+25;health=0.7;off=silenthill
id=fogday;track=sun;weather=fog;prio=5;off=mutants;fog=0.8;desat=0.4
```

By day they are off; the default Night and the foggy day leave them on, and the foggy day keeps its fog thick. Keep Silent Hill's own Monsters only at night and Monsters only in fog options off; the log warns if they are on. `weather=fog` is decided as the day begins: fog that rolls in later doesn't count.

## Risers

Killed zombies get back up with **[Relentless Dead](https://steamcommunity.com/sharedfiles/filedetails/?id=3824839394)** (Mod ID `RelentlessDead`), a separate mod that raises corpses. Crepuscular doesn't need it, but without it `rise=` and `wake=` do nothing: the log warns once when a definition marks corpses, and the Status says Relentless Dead is not loaded.

With Relentless Dead loaded, Crepuscular drives it:

- **`rise=`** of the definition in effect is the percent of the zombies killed that are marked to get back up, rolled for each zombie. Relentless Dead's own Rise chance option rests meanwhile.
- **`wake=`** of the definition in effect decides whether due corpses get up: a corpse that comes due while it is false waits for a definition with `wake=true`, such as the default Night. Corpses are checked every 10 in-game minutes, and the check at the minute a phase or event begins already sees it.
- **Monster kinds stay down:** a killed member of a kind (Cry of Fear and Silent Hill monsters, Volatiles, mutants, Zomboid Forge types, the Kinds option's and registered kinds) is never marked, unless [RiseKinds](#risekinds) lists its kind.
- **Cry of Fear and Silent Hill monsters** that rise lose the marks of their health buffer first, so in single player they don't skip their health and die again at once.
- **Each riser** gets the speed and health of the definition in effect as it gets up.

Everything else is Relentless Dead's, with its own options on its own sandbox page: how soon a marked corpse comes due, how often one body can rise, what keeps a corpse down (burning, Finish off, floor head hits, safehouses, its age), Bandits and headless corpses, and its Status. Its README has the details.

## Sky and fog

### Keys

| Key | Values | Sets |
|---|---|---|
| `sky` | `rrggbbaa` | Tints the light. `aa` is the strength, from `00` (none) to `ff` (full), for example `sky=ff964660`. |
| `fogcolor` | `rrggbb` | The fog's colour. It shows only with the improved fog, not with the legacy fog quality option. |
| `fog` | 0 to 1 | How thick the fog is. |
| `desat` | 0 to 1 | How grey the world looks by day. The game fades it out with the daylight, so it hardly shows in the middle of the night. |
| `dark` | 0 to 1 | The night strength. It brings out the stars, street lights and night sounds but doesn't darken a day; `ambient=` and `sky=` do. |
| `ambient` | 0 to 1 | The ambient light. The game's `NightDarkness` option sets how low it can go: `set.NightDarkness=1` (pitch black) lets it reach nearly black. |

- Each replaces the game's own value while the definition applies and gives it back afterwards. A value not set stays the game's. The defaults set none.
- `fog`, `desat`, `dark` and `ambient` can [grow](#growth); the colours can't.

### Timing in multiplayer

The server sets them, so players see a change within about an in-game minute, faded in over about 5 seconds, and players who join see it at once. In single player a change shows at once.

### What wins over them

- Admin climate overrides win.
- Rain and storms still mix in their own sky and fog.
- A value another mod sets in its place is left to that mod: Crepuscular doesn't set it again until its own value changes.
- A server whose `MaxFogIntensity` is below Normal caps `fog=`.
- Status lists the sky values Crepuscular set and which of them an admin or another mod has overridden or turned off.

### Fog is not only a look

The fog works like the game's own: zombies and players also see less far in it, zombies hear less and shots miss more. It sets only how thick the fog is, not the grey light natural fog brings with the weather. View distance can't be set directly; `fog=` shortens it as natural fog does. A `weather=fog` event counts the `fog=` in effect as fog.

### Single player and dedicated servers

In single player a darker sky or ambient light also makes players harder for zombies to spot, as the game's own darkness does. A dedicated server doesn't model light for zombie sight, so there a darker sky doesn't help players hide.

## Monster mods and kinds

A **kind** is a named group of special zombies from another mod. Each definition's `off=` lists the kinds that are off while it applies. A kind no definition turns off is left alone.

### Why every special-zombie mod needs a kind

Every special-zombie mod needs a kind, even one you never turn off. Without it Crepuscular treats its monsters as ordinary zombies and changes their speed and health, every in-game minute, on every game. Members of a kind keep their own speed and health.

### Built-in kinds

| Kind | Mod | Members |
|---|---|---|
| `mutants` | The Mutants | The zombies The Mutants says are mutants. |
| `cof` | Cry of Fear Monster NPCs | Its monsters. |
| `silenthill` | Silent Hill Monster NPCs | Its monsters, Pyramid Head among them: the zombies in its outfits (`SHM_` and the monster's name), told by their persistent outfit on the server and on every player's game. |
| `volatiles` | Blackout Predators | Its Volatiles: the zombies in the outfit its own code names (`BP_Volatile`), told by their persistent outfit on the server and on every player's game. |
| one per Zomboid Forge type | Zomboid Forge, for example The Last of Us Infected | The zombies of that type. The kind is the type's id with only A-Z, a-z, 0-9 and `_` kept, lowercased: `tlou_runner`, `tlou_stalker`, `tlou_clicker`, `tlou_bloater` for The Last of Us Infected's types as its own Lua names them. A fork may name them otherwise; Status lists the kinds it finds. `ZF_Zomboid`, the type of ordinary zombies, is no kind. |

A zombie belongs to the first kind it matches, in this order: `cof`, `silenthill`, `volatiles`, `mutants`, the kinds of the Kinds option in order, kinds other mods register, then Zomboid Forge's types. Bandits belong to no kind.

### The Kinds option

The **Monster kinds** option adds kinds by the outfit their monsters spawn in: `name=prefix,prefix;name=prefix`, for example `wraiths=ZW_,Wraith;husks=Husk_`.

- A zombie whose outfit name starts with one of the prefixes (upper and lower case don't matter) belongs to that kind.
- Names are made of a-z, 0-9 and `_`, and can't be `none` or a built-in kind's name. A bad entry is skipped and logged; the rest are kept.
- It reads the outfit a zombie spawned in (its persistent outfit). A mod that later re-dresses ordinary zombies in other clothes doesn't change that, so the Kinds option can't see its monsters; such a mod needs a kind [registered by code](#for-modders).

**Ready lines** (the builder adds them with one click):

| Mod | Line | Notes |
|---|---|---|
| Projeto Nemesis (Workshop 3706463588, needs ApocalipseBR Regiões) | `nemesis=Nemesis,MrX` | Multiplayer only: it spawns its boss only on a server, with nothing to cap how many are alive. Its OutfitName option is `Nemesis` by default; Mr X comes only when it lists `MrX` too. It reads its options once, as the server starts, so no `set.` can keep it to the night (its SpawnRollPercent can't go below 1 either), and `off=nemesis` only removes far ones without a target: new ones keep coming, each aimed at a player. |
| IZ Zombie Skins (Workshop 3746812626) | `izskins=AABoomer,AACharge,AACloaker,AADemolisher,AAExperiment,AAGoon,AAOgre,AARadiationZed,AARevenant,AARunnerZed,AASummoner,AATankyZed,AAToad,AAVolatile,AAWoodZed` | Multiplayer servers only: there the game dresses zombies in its skins' outfits as they spawn, and the line sees those. In single player it puts other clothes on ordinary zombies, which keep their own outfit, so the line catches nothing. With the line its skins keep their own abilities and health; those that don't run lose Crepuscular's day and night speed. |

Occult Zombies needs no line: its monsters are ordinary zombies in other clothes, with nothing of their own, so they keep Crepuscular's speed, health and rises.

### Turning a kind off: far removal

While a kind is off, each in-game minute up to `RemovalsPerMinute` of its members (50 by default, all kinds together) are removed from the server and from every player's game, if they:

- are alive and not being dragged;
- have no target;
- have no player within `KeepDistance` tiles (40 by default) in a straight line.

Keep `KeepDistance` beyond what players can see, or monsters vanish in view. A removal is not a kill: it leaves no corpse.

Turning a kind off can't keep a mod from making its monsters, except as The Mutants, Cry of Fear, Silent Hill and Blackout Predators allow below. Members nearby or with a target stay. `volatiles` is never removed: see [Blackout Predators](#blackout-predators).

### The Mutants

- While `mutants` is off, The Mutants makes no new mutants, and far mutants are removed. The default Night turns it off. Crepuscular stops new mutants through The Mutants' own ownership hook; a version without it gets an error in the log, and then only far mutants are removed.
- When The Mutants is loaded, members of every kind are never turned into mutants.
- **Offer zombies when mutants start** (`MutantRequeue`, off by default): when mutants come back on, the zombies already loaded are offered to The Mutants, up to 200 per in-game minute, so the ones it picks turn into mutants at once. Some may change in plain view. Off, The Mutants only looks at a zombie when it is next created or loaded.
- The Mutants decides how many mutants it makes when the game starts: `off=none` lets them appear but can't make more.

### Cry of Fear Monster NPCs

- While `cof` is off, its spawns are set to None on the server and on every player's game: the regular and special monsters' homes, the Human Flowers and the Sawrunner's night encounters. Far monsters are removed, their looping sounds stopped first.
- When `cof` is on again its own values come back, and, as with its own Night only option, every one of its homes may be filled again, killed monsters' homes too.
- For its monsters only at night, put `off=cof` in Day and keep Cry of Fear's own Night only option off. The log warns if it is on.
- Its spawn levels can be set per definition, for example `set.COF_Spawns.Regular=5` (High).
- `off=cof` without Cry of Fear installed does nothing, and the log says so.
- Since its version 0.68.48, Cry of Fear turns a monster it didn't make in this session into an ordinary zombie when its kind is switched off, and its levels at None count. So while `cof` is off, a Cry of Fear monster that loads in (an area that loads again, a restart, a single player load) becomes an ordinary zombie for good, and gets Crepuscular's speed and health. Its home is filled with a new monster when `cof` is on again. With the game's zombie population at None these are the only ordinary zombies. Human Flowers stay, and far ones are removed.

### Silent Hill Monster NPCs

Silent Hill Monster NPCs is built on the same framework as Cry of Fear Monster NPCs, by the same author, so Crepuscular treats it the same way.

- While `silenthill` is off, its two population levels (regular monsters and Pyramid Head) are set to None on the server and on every player's game. Far monsters are removed; it plays no looping sounds that would need stopping.
- When `silenthill` is on again its own values come back, and every one of its homes may be filled again, killed monsters' homes too, as its own Monsters only at night option does at dusk.
- As Cry of Fear does, it turns a monster that loads in while `silenthill` is off into an ordinary zombie for good, and fills its home with a new one when `silenthill` is on again.
- For its monsters only at night, put `off=silenthill` in Day; for night and fog, see [the worked example](#worked-examples). Keep its own Monsters only at night and Monsters only in fog options off: they would add their own clock or fog on top, and the log warns while a definition turns `silenthill` off.
- With its own Monsters only in fog option on, a definition's `fog=` brings its monsters out too while `silenthill` is on: the mod reads the fog players see, which includes `fog=`.
- Its population levels and Pyramid Head's switch can be set per definition: `set.SHM_Spawns.Regular=5` (High), `set.SHM_Spawns.PyramidHead=5`, `set.SHM_Creatures.PyramidHead=true`. Pyramid Head is off by default; when a definition that turns him on ends, no new one comes, and the mod turns one that loads in again into an ordinary zombie.
- Its monsters that go down instead of dying are still alive: Crepuscular leaves them alone. Finish them on the floor as the mod says; Relentless Dead's Finish off is for corpses.
- `off=silenthill` without Silent Hill Monster NPCs installed does nothing, and the log says so.

### Blackout Predators

Its Volatiles sleep in fixed nests by day and hunt at its night, when it also turns some ordinary zombies far from players into Volatiles: its night swap, 9 percent of those 25 or more tiles from every player by default.

- **Its night is Crepuscular's.** With `VolatilesFollowNight` (on by default), Crepuscular sets the mod's own night hours (its NightStartHour and DayStartHour, which it reads every in-game minute), so its night lasts while the Night or a moon event applies and its day while the Day or a sun event applies, forced phases too. The Volatiles leave their nests at Crepuscular's dusk and go back at its dawn, and the swapped ones flee and are removed by the mod, as at its own 06:00. Its double XP follows the same night.
- Its scream as its night begins comes once, at Crepuscular's dusk. In a night or day of 22 hours or more, such as a long moon event or an endless day, the two hours move on so that the night or day lasts, with no scream in it.
- With `VolatilesFollowNight` off its own hours decide, 00:00 to 06:00 by default, and a `set.` of them works as any other. While it is on, a `set.` of those two hours does nothing, and the log says so. The log also warns when the sandbox options give the two hours other values than the mod's own, since Crepuscular replaces them.
- **`off=volatiles` only stops the night swap** (its AmbientSpawnChancePercent set to 0). No Volatile is ever removed: the mod frees a nest's place only when its Volatile dies, so a removed one would leave the nest empty for good. Nests still fill their empty places when first loaded, and a killed nest Volatile never comes back, by the mod's own rule.
- **Nests only:** put `off=volatiles` in Night and in the moon events that set their own `off=`, or `set.BlackoutPredators.AmbientSpawnChancePercent=0` in Night, which moon events take from it; the builder's Blackout Predators picker writes the `set.` per definition. A night with the swap off still counts the far zombies it looks at as rolled, so after it fewer of the zombies still loaded are swapped, until they unload.
- **The swap takes other mods' monsters too.** It picks any zombie 25 or more tiles from every player that isn't a Volatile already: Cry of Fear and Silent Hill monsters and mutants as well, whatever their kinds. Only turning the swap off prevents it.
- Volatiles keep the mod's own speed and health, aren't marked to rise unless `RiseKinds` lists `volatiles`, and The Mutants never converts them.
- `volatiles` is built in: a `volatiles=` line in the Kinds option is an error now, so remove it.
- Its options can be set per definition with `set.`, and it reads them within an in-game minute: `AmbientSpawnChancePercent`, `UVMechanicsEnabled` (a night when the lamps fail), `VolatileSpeedScale`, `VolatileStrength`, `VolatileSight`, `VolatileMemory`, `VolatileHearing`. A `VolatileHealth` changed mid-game reaches only some Volatiles, and lower nest counts retire live ones.
- `off=volatiles` without Blackout Predators installed does nothing, and the log says so.

### Zomboid Forge

- A Zomboid Forge kind that is off only loses its far members: Zomboid Forge goes on giving its types to new zombies, and its spawn shares are fixed when the world loads.
- With The Last of Us Infected and without the Zomboid Forge [Zomboids] add-on, Zomboid Forge gives every zombie a type, so every zombie is a member of a kind: Crepuscular's speed and health then change no zombie, and The Mutants makes no mutants. This comes from reading Zomboid Forge's source.
- Zomboid Forge writes `ZombieLore.Sight`, `Hearing`, `Cognition`, `Memory`, `Strength` and `Toughness` as it sets up each zombie, so `set.` entries for those options fight it.

### RiseKinds

**Monster kinds that rise** (`RiseKinds`) only matters with Relentless Dead. It lists the kinds whose killed members can be marked to rise too, written as in `off=`: for example `cof,mutants`, `tlou_clicker`, or a kind of the Kinds option. Empty, only ordinary zombies rise. Bandits never rise. A monster rises as any corpse does, in the same outfit; what it can do after that is up to its own mod. A list that isn't kind names separated by commas is logged and no monster rises; a name that isn't a known kind is logged too. `silenthill` there adds Crepuscular's rises on top of the mod's own going down: a monster finished on the floor could get up again later. `volatiles` there lets a Volatile's corpse rise with the mod's marks on it; how the mod then treats it is untested, so it is not recommended.

## Presets and examples

The builder has presets for Day, Night or an event, and ready example events. They live only in the builder: applying one writes the definition text, which is all the mod reads. Applying a preset replaces the zombie keys (`speed`, `steps`, `health`, `rise`, `wake`, `off`) and every key it lists, and keeps the event's conditions and other keys.

| Group | Inspired by |
|---|---|
| Herd | Night of the Living Dead, Dawn of the Dead (1978), The Walking Dead and World War Z (novel) |
| Frenzy | 28 Days Later, Dawn of the Dead (2004), Train to Busan, [REC], Zombieland and DayZ |
| Horde rush | Left 4 Dead 2, World War Z (film) and Days Gone |
| Nightmare town | Silent Hill and Cry of Fear |
| Fog world | Silent Hill |
| Lab leak | Resident Evil |
| Night hunters | I Am Legend, Dying Light and Kingdom |
| Spore bloom | The Last of Us |
| Grave rise | Army of Darkness and Return of the Living Dead |
| More moons and suns | none |

| Group | Name | Type | What it does | Needs |
|---|---|---|---|---|
| Herd | Herd | Preset | Slow dead in large groups that gather and bang on doors and walls even with no one to chase. No monsters, washed-out colour, and a far-off shot as it begins. | |
| Herd | Black and white | Preset | The herd in grey: the world loses all its colour. | |
| Herd | Herd (`herd`) | Example | A herd passes every 8 to 14 days after the first week, for a day and the night after it. Anyone who dies while it lasts turns. | |
| Herd | Hard freeze (`hardfreeze`) | Example | On nights at -5 °C or colder the dead are slow and stiff: every ordinary zombie is a shambler. | |
| Frenzy | Frenzy | Preset | Sprinting, fragile infected who die like people. A bite turns within hours, and nothing gets back up. | |
| Frenzy | Double tap | Preset | Fast and bright, and some of the dead get up again: make sure they stay down. | |
| Frenzy | Starving | Preset | Sprinters who waste away: their health falls from full to 40 percent between world days 28 and 84. For Day or Night, with no line of its own. | |
| Frenzy | Frenzy (`frenzy`) | Example | Rare: from day 3, at most every 20 days, a day and the night after it of sprinters. | |
| Frenzy | Blackout (`blackout`) | Example | A rare night from day 5 when the lights fail: pitch black, with sprinting infected. | |
| Horde rush | Horde rush | Preset | Many fast but fragile zombies that pile against fences and gather in big groups, mutants among them, with distant gunfire often. | The Mutants |
| Horde rush | Growing hordes | Preset | The horde rush, faster as the world ages: from a quarter of the zombies faster on world day 10 to 60 percent on world day 90. | The Mutants |
| Horde rush | Horde storm (`hordestorm`) | Example | Stormy or rainy afternoons from day 5, at most weekly: six hours of horde rush from 14:00. | The Mutants |
| Nightmare town | Fog town | Preset | Thick, pale fog and slow zombies; Cry of Fear monsters at their highest are the threat. Best by day. | Cry of Fear Monster NPCs |
| Nightmare town | Nightmare | Preset | Near-black, rust-red light, a thin dark fog and Cry of Fear monsters at their highest. Best by night. | Cry of Fear Monster NPCs |
| Nightmare town | Fog town, then the nightmare (`fogtown`, `nightmare`) | Example | A foggy day becomes Fog town, at most every 14 days, and the night after it may turn into the Nightmare. Both are added, the second chained after the first. | Cry of Fear Monster NPCs |
| Fog world | Fog world | Preset | A white fog over a washed-out town, slow zombies, and Silent Hill monsters at their most as the threat. Best by day. | Silent Hill Monster NPCs |
| Fog world | Siren night | Preset | Near-black, rust-red light and a thin dark fog, with Silent Hill monsters at their most. Best by night. | Silent Hill Monster NPCs |
| Fog world | Fog world, then the siren (`fogworld`, `sirennight`) | Example | A foggy day becomes the Fog world, at most every 7 days, and the night after it may turn into the Siren night. Both are added, the second chained after the first. | Silent Hill Monster NPCs |
| Fog world | Judgement (`judgement`) | Example | A rare night from day 14, at most every 21 days: Pyramid Head walks, few other monsters, and the dark is rust-red. | Silent Hill Monster NPCs |
| Fog world | Silent Hill monsters at night and in fog (`fogday`) | Example | With off=silenthill in Day, Silent Hill monsters roam by night and on foggy days. This adds the foggy day, which also thickens the fog; put off=silenthill in Day yourself. | Silent Hill Monster NPCs |
| Lab leak | Lab leak | Preset | Slow, tough dead with mutants among them, and a third of the kills get back up unless burned or finished off. Thunder as it begins. | The Mutants |
| Lab leak | Lab leak (`lableak`) | Example | Stormy or rainy nights from day 10, at most every 10 days. | The Mutants |
| Night hunters | Sun-weakened | Preset | Every ordinary zombie a tier slower and fragile, those already around too. For Day, with Night hunters for Night. | |
| Night hunters | Night hunters | Preset | Half of the zombies sprint, the ones that come in are tougher, and the night is pitch black. For Night, with Sun-weakened for Day. | |
| Night hunters | Moonless (`moonless`) | Example | New-moon nights are worse: faster, tougher and darker still. | |
| Night hunters | Cold snap (`coldsnap`) | Example | On a day at 5 °C or colder, at most every 3 days, they don't sleep: as fast and tough as Night hunters. | |
| Spore bloom | Spore bloom | Preset | Zombies that see poorly but hear everything, a third of them faster and all tougher, in a yellow haze. Sneaking works; gunfire doesn't. | |
| Spore bloom | Spore bloom (`sporebloom`) | Example | Foggy or rainy days from June to October, from day 14 and at most every 15 days: three days of spore bloom. | |
| Grave rise | Grave rise | Preset | Most of the dead get back up, tougher, and bang on doors and walls under a pale mist. Only fire or Finish off keeps them down. | |
| Grave rise | Grave rise (`graverise`) | Example | Some full moons from day 14, at most every 20 days; it beats the blood moon when it rolls. | |
| Grave rise | Black rain (`blackrain`) | Example | Rainy nights from day 14, at most every 10 days: fast dead, and most of them get back up. | |
| More moons and suns | Blue moon (`bluemoon`) | Example | Every 4th full moon: the dead are slow, but every one killed gets back up, under a blue light. | |
| More moons and suns | Green moon (`greenmoon`) | Example | One new moon in ten: a sickly green fog, and Cry of Fear monsters at their highest. | Cry of Fear Monster NPCs |
| More moons and suns | Red sun and the long night after it (`redsun`, `longnight`) | Example | On 15 percent of summer days every ordinary zombie sprints, and half the time the night after lasts three and a half days. Both are added, the long night chained after the red sun. | |
| More moons and suns | Eclipse (`eclipse`) | Example | About once a year, on a new moon: two dark hours from noon, and the dead get back up. | |
| More moons and suns | Halloween (`halloween`) | Example | Every 31 October, above everything else: every kill gets back up, monsters are out, and an orange glow. | Cry of Fear Monster NPCs |
| More moons and suns | Bright moon every 30 days (`fullmoon`) | Example | Every 30 days from world day 30: a line, nothing else. It counts world days, not the moon. | |

- **Needs:** without The Mutants, no mutants appear, whatever `off=` allows. Without Cry of Fear Monster NPCs, the game skips the `set.COF_Spawns` values with a warning, and no Cry of Fear monster appears. Without Silent Hill Monster NPCs, the game skips the `set.SHM_` values with a warning, and no Silent Hill monster appears.
- The presets without monsters turn `cof` and `silenthill` off together; the log notes each of those mods that isn't installed.
- The sky values of the presets are a first guess, not yet tuned in game.
- The builder shows each preset's notes, for example which of its `set.` values stick to zombies after it ends.

## All sandbox options

Each option is `Crepuscular.<Option>` in the sandbox settings, on the **Crepuscular** page.

| Option | In game | Default | Range | What it does |
|---|---|---|---|---|
| `NightMode` | Night mode | `1` (Fixed hours) | 1 Fixed hours, 2 Seasonal night | How night is decided: fixed hours, or the game's seasonal dusk and dawn. |
| `NightStartHour` | Night starts at | `20` | 0 to 23 | Hour night begins with fixed hours. The same hour for both means no night. |
| `NightEndHour` | Night ends at | `4` | 0 to 23 | Hour night ends with fixed hours. |
| `Day` | Day | [see above](#the-defaults) | text | The [definition](#definitions-day-night-and-events) in effect by day while no event runs. |
| `Night` | Night | [see above](#the-defaults) | text | The definition in effect by night while no event runs. |
| `Events1` | Events 1 | [see above](#the-defaults) | text | [Events](#events-reference), separated by `\|`. The default is the blood moon. |
| `Events2` | Events 2 | empty | text | More events, written as in Events 1. |
| `Events3` | Events 3 | empty | text | More events, written as in Events 1. |
| `Events4` | Events 4 | empty | text | More events, written as in Events 1. |
| `Events5` | Events 5 | empty | text | More events, written as in Events 1. |
| `Events6` | Events 6 | empty | text | More events, written as in Events 1. |
| `Events7` | Events 7 | empty | text | More events, written as in Events 1. |
| `Events8` | Events 8 | empty | text | More events, written as in Events 1. |
| `Kinds` | Monster kinds | empty | text | [Monster kinds](#the-kinds-option) told by their outfit: `name=prefix,prefix;name=prefix`. |
| `KeepDistance` | Keep distance | `40` | 0 to 300 | While a kind is off, a member is removed only with no target and no player within this many tiles. |
| `RemovalsPerMinute` | Removals per minute | `50` | 1 to 500 | Most far members of kinds that are off removed per in-game minute, all kinds together. |
| `MutantRequeue` | Offer zombies when mutants start | `false` | true or false | When mutants come back on, offer the loaded zombies to The Mutants (200 per minute). |
| `VolatilesFollowNight` | Volatiles follow the night | `true` | true or false | [Blackout Predators](#blackout-predators)' night is Crepuscular's: it sets the mod's own night hours. |
| `ZombiesPerSweep` | Zombies per sweep | `400` | 50 to 5000 | Zombies checked per in-game minute on each game for the speed and health in effect. |
| `RiseKinds` | Monster kinds that rise | empty | text | With Relentless Dead: monster kinds whose killed members can be marked to rise too, as in `off=`. |
| `Notifications` | Notifications | `true` | true or false | Show the definitions' lines (`say=`) and play their sounds (`sound=`) to players. |
| `NotificationPlace` | Where lines show | `1` (Over the head) | 1 Over the head, 2 In chat, 3 Over the head and in chat | Where players see the definitions' lines: over their heads, in chat (multiplayer only) or both. |
| `Verbose` | Verbose log | `false` | true or false | Write phase changes, each decision with its rolls, event starts and ends, sandbox value changes, removals and mutant requeues to the log. |

An option with a value the game shouldn't hold is replaced by its default, and the log warns. Warnings and errors, such as mistakes in the definitions, are always logged, prefixed `[Crepuscular]`.

## Admin menu and Status

Right-click the world: the **Crepuscular** entry is there in single player, and in multiplayer for players whose role has the sandbox options permission (admins). The server refuses anyone else.

| Entry | What it does |
|---|---|
| **Status** | A summary on screen: the phase, the event, how many events loaded, definitions with errors and options overridden. The full report goes to the log. |
| **Force phase:** Automatic, Day, Night | Applies Day's or Night's definition whatever the clock says, until set back to Automatic or the game restarts (it isn't saved). A running event still applies. Decisions still follow the clock, and the phase's line isn't shown. |
| **Start event:** each loaded event | Ends the current event and starts this one now, whatever its conditions and `at=`. It counts as a start for `cooldown=` and `interval=`. |
| **End event** | Ends the running event, or drops one waiting for its start time. |
| **Re-decide this occasion** | Picks again for the current night or day with fresh rolls, without counting `nth=` again, and starts the choice now (or at its `at=` time if that is still ahead). It refuses while an event runs: end it first. |

When the definitions have errors, admins see "Crepuscular: N definitions have errors, see Status." as they join.

**The Status report** goes to the log of the admin's game (`Zomboid/console.txt`), and on a server to the server's log too. It holds:

- the mod version, the clock, the phase (and whether it is forced), the occasion and the world day;
- today's moon phase, computed and as the game shows it;
- for each track, the last decision and its candidates, or the event covering it;
- the current event, since when and until when, or what it waits for;
- the events loaded, every error and warning, and each event's counts, last start, cooldown, when its interval is due and waiting chain flags;
- every kind and where it comes from, the kinds off now and the far members removed this session;
- the speed, steps and health in effect, and a count of the loaded ordinary zombies by speed tier, with their health;
- Relentless Dead's own Status lines (the rise and wake in effect, corpses registered and due, the last check, this session's counts), or that it is not loaded;
- the sky values Crepuscular set and which of them an admin or another mod has overridden or turned off;
- the sandbox values overridden now, with their bases, and any the game refused;
- each text option's size in bytes;
- the state of The Mutants, Cry of Fear, Silent Hill, Blackout Predators and Zomboid Forge support.

## Multiplayer and performance

| Where | What runs |
|---|---|
| The server (or the single player game) | Each in-game minute, the speed of the zombies no player's game runs and the health cap of every zombie it has loaded. The clock and the decisions, kept in the save. Sandbox values, sent to every player. The sky and fog. Driving Relentless Dead with `rise=` and `wake=`. Far removal. The Mutants, Cry of Fear, Silent Hill and Blackout Predators support. The admin commands. The speed and health of the zombies it creates, loads or raises. |
| Every player's game | Each in-game minute, the speed of the zombies that game runs and the health cap of every zombie it has loaded. The lines and sounds. Removing its copies of the monsters the server removed. Taking the server's sandbox values. |

The server sends its state to players whenever it changes, and a player who joins gets it at once.

| Option | Cost |
|---|---|
| `ZombiesPerSweep` (400) | Zombies each game checks per in-game minute. More is quicker after a change and costs more time each minute. |
| `RemovalsPerMinute` (50) | Far monsters removed per minute; every player's game is told to remove its copy of each one. |
| `MutantRequeue` (off) | Up to 200 zombies offered to The Mutants per minute when mutants come back on. |
| `Verbose` (off) | Every decision, change and removal written to the log. |

## For modders

`Crepuscular.API` is a global on the server, in single player and on players' games. Its `VERSION` is 1.

| Function | Returns |
|---|---|
| `Crepuscular.API.registerKind(name, spec)` | `true`, or `false` and why. Registers a kind of your monsters. |
| `Crepuscular.API.isActive(name)` | Whether the kind is active in the definition in effect. Kinds no definition turns off are, and so is every kind while this game has no state yet. |
| `Crepuscular.API.kindOf(z)` | The kind of zombie `z`, or `nil`. |
| `Crepuscular.API.current()` | `{ phase = "day" or "night", event, track, serial }`, with `event`, `track` and `serial` only while an event runs, or `nil` while this game has no state yet. It is a copy. |

**registerKind(name, spec):**

- `name`: a-z, 0-9 and `_`. Not `none`, `cof`, `silenthill`, `volatiles`, `mutants`, the kind of a Zomboid Forge type, or a kind of the Kinds option. Zomboid Forge's types are known once the game has started: a kind registered before under the name of one is set aside then, with a warning.
- `spec.isMember(z)`: returns whether `z` is a member. It runs on the server and on players' games, and must give the same answer on both: members keep their own speed and health on every game, so a member `isMember` misses on the player's game that runs it gets capped there, and the server takes that health. One that throws counts as no member, with a warning.
- `spec.despawn = false`: keeps far members while the kind is off.
- The same name again replaces its spec. A Kinds option entry with the same name replaces the registered kind, with a warning.

**OnCrepuscularChange(current, previous):** an event that fires once the game has started and whenever the phase or the running event changes after that. `current` is what `current()` returns; `previous` is the one before, `nil` the first time. It fires on the server, in single player and on players' games.

```lua
-- media/lua/shared/MyMod/CrepuscularSupport.lua
if getActivatedMods():contains("\\Crepuscular") then
    local API = require "Crepuscular/API"

    API.registerKind("wraiths", {
        -- Must answer the same on the server and on every player's game.
        isMember = function(z)
            return MyMod.isWraith(z)
        end,
    })

    Events.OnCrepuscularChange.Add(function(current, previous)
        if current.event == "bloodmoon" and (previous == nil or previous.event ~= "bloodmoon") then
            -- a blood moon has begun
        end
    end)
end
```

`require "Crepuscular/API"` loads the API whichever mod loads first, and creates `Events.OnCrepuscularChange`. Build 42 lists mod ids with a leading backslash, hence `"\\Crepuscular"`.

## Compatibility

From the mods' descriptions and, where it is public, their code. None of these was tested together with Crepuscular.

**Conflict.** Crepuscular sets ordinary zombies' speed again every in-game minute, so these fight it:

- mods with their own day and night or darkness speeds: They Fear the Light, Nightmares, PhunSprinters 2, Random Zeds, Night Sprinters (Dusk and Dawn), the Time and Moon modules of Definitive Zombies;
- The Darkness Is Coming 2, unless its zombie mutation option is off (its fog and darkness otherwise fit);
- mods that turn ordinary zombies into runners: Screamer Zed, the Virals of Blackout Predators Extended, Necroa;
- speed overhauls whose specials have no kind yet: CDDA Zombies, ZED+, and ApocalipseBR Regiões' speed overrides in the regions an admin sets up;
- the game's own `ZombieLore.Speed` set to Sprinters, or `ZombieLore.ActiveOnly` other than Both (the log warns).

**Fit well:**

- The Mutants, Cry of Fear Monster NPCs, Silent Hill Monster NPCs, Blackout Predators and Zomboid Forge (The Last of Us Infected): built-in kinds.
- Projeto Nemesis, and IZ Zombie Skins on multiplayer servers: [ready Kinds lines](#the-kinds-option).
- Occult Zombies: nothing to set up, its monsters are ordinary zombies.
- Relentless Dead: raises the corpses `rise=` marks, driven by the definition in effect (see [Risers](#risers)).
- Bandits: they never rise, keep their own speed and belong to no kind.
- Kill counters and XP mods: each rise is another kill.
- Scheduled horde mods (Dynamic Horde Events, Blood Moon Hordes, Hark's Horde Night Revamped, Horde Night Revived) and night-only creature mods with their own clock (Dark Presence): their own options can be switched per definition with `set.`. Whether each reads its options while the game runs is unverified.

## Known limitations

- **Fog** changes sight and hearing, not just the look: zombies and players see less far, zombies hear less, shots miss more.
- **`desat=`** shows by day; the game fades it out at night.
- **`dark=`** doesn't darken a day; use `ambient=` or `sky=`.
- **`fogcolor=`** shows only with the improved fog. A `MaxFogIntensity` below Normal caps `fog=`. Rain, storms and admin climate overrides win over the sky values.
- **Light and zombie sight:** a darker sky helps players hide only in single player.
- **`sound=`** is not a world sound: zombies don't hear it.
- **`rise=` and `wake=`** do nothing without Relentless Dead.
- **Some `set.` values** apply only to zombies created or loaded later, stick to infections or bodies, or need a restart. See [Sandbox values](#sandbox-values-set).
- **`off=`** removes only far members without a target, and never a Volatile. Only The Mutants, Cry of Fear and Silent Hill also stop making new ones, and Blackout Predators its night swap; other mods go on making their monsters.
- **Blackout Predators' night swap** can turn any far zombie into a Volatile, other mods' monsters too, whatever their kinds; only turning the swap off prevents it.
- **Cry of Fear and Silent Hill** turn their monsters that load in while their kind is off into ordinary zombies, for good.
- **A special-zombie mod without a kind** gets Crepuscular's speed and health on its monsters.
- **Forcing a phase** isn't saved, and doesn't change the game's time or which events are decided.
- **Each text option** must stay under 32000 bytes.

## Not yet verified in game

- The sound names the presets use, and that each plays once.
- The sky values of the presets, and which of `ambient=`, `dark=` and `sky=` darken a long night's day.
- The multiplayer timing of the sky values, and a join, a restart or an admin override in the middle of an event.
- That a sprint set by Crepuscular is full speed on the player's game that runs the zombie in multiplayer.
- Relentless Dead driven by the definitions: that a night's kills rise at night only, and the blood moon's at once, with the speed and health of the definition in effect.
- Cry of Fear: that removing a monster stops its looping sounds, and the Sawrunner's night encounters, which the server can't tell apart.
- Silent Hill Monster NPCs: that its monsters are members on the server, in single player and on players' games; `off=silenthill` (no new spawns, far ones removed, no ghosts on players' games, homes filled again at dusk); that a `fog=` brings out its fog-only spawns; `set.SHM_Creatures.PyramidHead` turned on and off mid-game; and its multiplayer, which its author has not tested yet.
- Zomboid Forge: the Build 42.20 Workshop forks (their module and type ids), that the server and players' games agree on each zombie's kind, `set.ZombieLore.Sight` and `Hearing` against Zomboid Forge's own writes, and that far removal leaves no lingering sounds.
- Blackout Predators: that its Volatiles are members on the server, in single player and on players' games; that they leave their nests at Crepuscular's dusk and go back at its dawn, with its scream once at dusk, on a server too, where its players get the hours through its own sync; `off=volatiles` (no swaps, no Volatile removed); and the warning about the sandbox's own hours, which reads the options' defaults from the game.

## Reporting problems

Open an issue at [github.com/zexyqag/Crepuscular/issues](https://github.com/zexyqag/Crepuscular/issues) with:

1. single player or server, and the game version;
2. your Crepuscular options (the builder's Export, or the `Crepuscular` table of `SandboxVars.lua`);
3. the Status report and the `[Crepuscular]` lines from the log (`Zomboid/console.txt`, or the server's log), with **Verbose log** on if you can;
4. your other mods, especially monster and speed mods;
5. what you expected and what happened.

## Publishing

Run the **Publish** workflow (Actions, Publish, Run workflow), optionally with notes for the top of the change log. It starts from the latest version: the highest `vX.Y.Z` release, or while there is none, the highest `vX.Y.Z` tag. Then:

- **A release** when a commit since then is releasable (below) and something under `Contents/` changed. It is tagged `vX.Y.Z`, its notes are the change log (your notes, then the breaking changes, features and fixes from the commit messages), and `Contents/` and `preview.png` are uploaded to the Workshop item in `workshop.txt`'s `id=`, with the change log as the Steam change note.
- **Only the Workshop page** is updated when the title, description or visibility in `workshop.txt`, or `preview.png`, changed.
- **Nothing** otherwise.

| Commit message | From 0.9.0 | From 1.4.2 |
|---|---|---|
| `fix: ...` | 0.9.1 | 1.4.3 |
| `feat: ...` | 0.10.0 | 1.5.0 |
| `feat!: ...` (any type with `!`), or a `BREAKING CHANGE:` footer | 0.10.0 | 2.0.0 |
| any other type (`docs:`, `chore:`, ...) or message | no release | no release |

A scope is fine (`fix(fog): ...`), and the highest of the commits counts. While MAJOR is 0, a breaking change raises MINOR, as a feature does. A `Release-As: X.Y.Z` footer sets the version instead; it must be higher than the latest. That is how 1.0.0 is made.

The version is set by Publish: `mod.info` has no `modversion=` line in the repository, and Publish writes it into the uploaded copy. When the upload fails, the release stays a pre-release, and the next run uploads it again before it publishes anything newer. The builder is not part of a release: GitHub Pages serves `builder/` from the main branch.

Setup: the `steam` environment holds the secrets `STEAM_USERNAME` and `STEAM_CONFIG_VDF` (steamcmd's `config/config.vdf` after a login with Steam Guard). Upload the item once from the game, which creates it and writes its `id=` into `workshop.txt`, commit that, and tag the commit you uploaded with its version (`git tag v0.1.0 <commit>`, then push the tag).
