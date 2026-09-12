ApolloGenome a Hermes fork Pandora MacOS client for Intel and Apple Silicon
======
<img width="529" height="394" alt="image" src="https://github.com/user-attachments/assets/972526c9-c868-4429-b1e6-1d0245481f55" />

Picture ApolloGenome/2.01b1 running on Macbook Air M1 Apple Silicon Tahoe 26

Forked from Hermes built in XCode 26 on MacOS 26 Apple Silicon as Apple Silicon app for the universal notarized app

Includes music genome project data when playing song information(toggleable). Station modes added (note might not work on paid pandora plus versions)

UI redesigned due to deprecation of drawers. Now with more modern flat layout using nssplitviews. A lot of the UI bugs are from old UI in interface builder using constraints rather than modern programatic swift UI.

A [Pandora](http://www.pandora.com/) client for macOS Intel and Apple Silicon.

**Bug workarounds:**

Known bug: The 2.0.0b1 refactor introduced a bug that can occasionally cause audio skipping in the beginning  of a track from lost frames. *edit* the audio skipping bug is fixed in 2.0.1b1. Thanks to ASegner.

Old behavior is the player would stop and throw an error to restart the playback from beginning. This should be fixed in 200b5.

B10 and B11 have heightened security permissions. B11 has hardened runtime. Try downloading b9 and running it before be b10 and b11.

*edit* media keys old code updated in 2.0.1b1. Thanks to ASegner again.
Media keys in b11 and probably b10 will require heightened permissions accessibility and input monitoring enabled manually for Hermes after starting for the first time. 

System Settings → Privacy & Security → Accessibility
System Settings → Privacy & Security → Input Monitoring

*edit* scroll views redesigned in 2.0.1b1. Thanks to ASegner again.
If installing B11 and the scroll views for stations and history are not centered expand the window to fit them and restart they recenter on restart.

For b11 adding a station has to be done manually from toolbar. At top menu click Pandora > New / Edit / Reload stations 

Removing a station will have to be done from pandora in web browser. Should be fixed in the menu.

The play / pause button now says play. It still pauses when pressed. FIXED

New delete station menu button causes UI glitch. Double click a station to play and restart. should be fixed.

email pw login bug should be fixed. Should be able to click login. Previously required tab and enter keys.


### THIS PROJECT IS MAINTAINED BUT VOLUNTEERS TO TEST ARE WELCOME
Thanks to ASegner and MichaelFoss for contributing pull requests and everyone else for testing. 

This means that bugs are documented and workarounds can be attempted.

New features will happen slowly.

You can also make pull requests and add to issues and I will try to reply.

### Download ApolloGenome

- Click Download in the releases source code also provided with most apps

- On newer MAC OS download the app, extract if needed, double click to open, on warning message, open again, go to system settings, privacy and security, scroll to the bottom and click open anyways, open the app enter your password should open normally after.

### Install with Homebrew

This repository can be added directly as a Homebrew tap. Install the latest
universal release (Intel and Apple Silicon) with:

```sh
brew tap dtseto/hermes-master https://github.com/dtseto/Hermes-master.git
brew trust dtseto/hermes-master
brew install --cask apollogene
```

Homebrew installs the application as `ApolloGene.app`. To upgrade or uninstall
it later, run `brew upgrade --cask apollogene` or
`brew uninstall --cask apollogene`.

If you would like to compile Hermes, continue reading.

### Develop against ApolloGenome

- Adding stations type controls like Crowd Faves, Deep Cuts instead of only My Station default
* stations mode can be changed but oddly only work on free pandora.
  
- Possible features fixing proxy bugs better error message display
* need proxy mode testers

- Improve support for later MacOS currently written for 10.10+ rewrite for 11+ (implemented now important since Rosetta being removed future xcodes version target 11+), setup app sandboxing (not yet but hardened runtime enabled), app notarization(done), use new keychain code(done), 

- Hard redesign for UI in swift instead of interface builder (probably not since Hermes is forked from pianobar written in C)(still pending to rewrite to use swift instead of interface builder),
* New design using hstack vstack is much faster and less buggy. *edit again* Redesigned from the old drawer view to none, to stack view, to nssplitview to reproduce the old drawers in a modern format. Less need to update to swiftui.

- Need to split large files like audiostreamer to make it easier to maintain. * Partly done for audiostreamer.

- Need more unit tests. *mostly done)

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
