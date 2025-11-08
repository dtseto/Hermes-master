ApolloGenome a Hermes fork Pandora MacOS client for Intel and Apple Silicon
======
<img width="828" height="734" alt="Screenshot 2025-07-18 at 3 08 02 PM" src="https://github.com/user-attachments/assets/b8fce636-3fb7-40de-b570-22a2865d5f0c" />

Picture ApolloGenome/Hermes 1.32b11 running on Macbook Air M1 Apple Silicon Sequoia 15.5

Forked from Hermes built in XCode 16 on MacOS 15 Apple Silicon as Apple Silicon app for the universal notarized app

Includes music genome project data when playing song information. Station modes not stable so were removed.

UI redesigned due to deprecation of drawers. Now with more modern flat layout. A lot of the UI bugs are from old UI in interface builder using constraints rather than modern programatic swift UI.

A [Pandora](http://www.pandora.com/) client for macOS Intel and Apple Silicon.

**Bug workarounds:**

Known bug: The 2.0.0b1 refactor introduced a bug that can occasionaly cause audio skipping in the beginning  of a track from lost frames.

B10 and B11 have heightened security permissions. B11 has hardened runtime. Try downloading b9 and running it before be b10 and b11.

Media keys in b11 and probably b10 will require heightened permissions accessibility and input monitoring enabled manually for Hermes after starting for the first time.

System Settings → Privacy & Security → Accessibility
System Settings → Privacy & Security → Input Monitoring

If installing B11 and the scroll views for stations and history are not centered expand the window to fit them and restart they recenter on restart.

For b11 adding a station has to be done manually from toolbar. At top menu click Pandora > New / Edit / Reload stations 

Removing a station will have to be done from pandora in web browser. Should be fixed.

The play / pause button now says play. It still pauses when pressed. FIXED

New delete station menu button causes UI glitch. Double click a station to play and restart. should be fixed.

### THIS PROJECT IS MAINTAINED BUT VOLUNTEERS TO TEST ARE WELCOME

This means that bugs are documented and workarounds can be attempted.

New features will happen slowly.

You can also make pull requests and add to issues and I will try to reply.

### Download ApolloGenome

- Click Download in the releases source code also provided with most apps

- On newer MAC OS download the app, extract if needed, double click to open, on warning message, open again, go to system settings, privacy and security, scroll to the bottom and click open anyways, open the app enter your password should open normally after.

If you would like to compile Hermes, continue reading.

### Develop against ApolloGenome

- Adding stations type controls like Crowd Faves, Deep Cuts instead of only My Station default
  
- Possible features fixing proxy bugs better error message display

- Improve support for later MacOS currently written for 10.10+ rewrite for 11+ (implemented now), setup app sandboxing (not yet but hardened runtime enabled), app notarization(done), use new keychain code(done), 

- Hard redesign for UI in swift instead of interface builder (probably not since Hermes is forked from pianobar written in C)(still pending to rewrite to use swift instead of interface builder)

- Need to split large files like audiostreamer to make it easier to maintain.

Below for Hermes
Thanks to the suggestions by [blalor](https://github.com/blalor), there's a few
ways you can develop against Hermes if you really want to.

1. `NSDistributedNotificationCenter` - Every time a new song plays, a
   notification is posted with the name `hermes.song` under the object `hermes`
   with `userInfo` as a dictionary representing the song being played. See
   [Song.m](https://github.com/HermesApp/Hermes/blob/master/Sources/Pandora/Song.m#L29)
   for the keys available to you.

2. AppleScript - here's an example script:

        tell application "Hermes"
          play          -- resumes playback, does nothing if playing
          pause         -- pauses playback, does nothing if not playing
          playpause     -- toggles playback between pause/play
          next song     -- goes to the next song
          get playback state
          set playback state to playing

          thumbs up     -- likes the current song
          thumbs down   -- dislikes the current song, going to another one
          tired of song -- sets the current song as being "tired of"

          raise volume  -- raises the volume partially
          lower volume  -- lowers the volume partially
          full volume   -- raises volume to max
          mute          -- mutes the volume
          unmute        -- unmutes the volume to the last state from mute

          -- integer 0 to 100 for the volume
          get playback volume
          set playback volume to 92

          -- Working with the current station
          set stationName to the current station's name
          set stationId to station 2's stationId
          set the current station to station 4

          -- Getting information from the current song
          set title to the current song's title
          set artist to the current song's artist
          set album to the current song's album
          ... etc
        end tell

### Want something new/fixed?

1. [Open a ticket](https://github.com/HermesApp/Hermes/issues)! We'll get
   around to it soon, especially if it sounds appealing to us. We take all
   suggestions/feedback!

2. Take a stab at it yourself if you're brave. Just send us a pull request if
   you've got something fixed. Here's some common things to do at the command
   line:

        make        # build everything
        make run    # build and run the application (logging to stdout)
        make dbg    # build and run inside LLDB

        # Build with the 'Release' configuration instead of 'Debug'
        make CONFIGURATION=Release [run|dbg]

   Please note that Media Key shortcuts
   [will not work](https://github.com/nevyn/SPMediaKeyTap/blob/master/SPMediaKeyTap.m#L108)
   if compiled with `CONFIGURATION=Debug` (the default).

## License

Code is available under the [MIT
License](https://github.com/HermesApp/Hermes/blob/master/LICENSE).
