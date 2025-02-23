ApolloGenome a Hermes fork Pandora MacOS client for Intel and Apple Silicon
======
![image](https://github.com/user-attachments/assets/9e8fdbfe-ff6c-4558-9993-4403acd2368b)

Picture ApolloGenome/Hermes 1.32b4 running on Macbook Air M1 Apple Silicon Sequoia 15.1

Forked from Hermes built in XCode 16 on MacOS 15 Apple Silicon as Apple Silicon app for the universal app for intel use older 1.32b4 with ui fixes

Includes music genome project data when playing song information. Station modes not stable so were removed.

A [Pandora](http://www.pandora.com/) client for macOS Intel and Apple Silicon.

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

- Improve support for later MacOS currently written for 10.10+ rewrite for 11+, setup app sandboxing, app notarization, use new keychain code, 

- Hard redesign for swift instead of interface builder (probably not since Hermes is forked from pianobar written in C)

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
