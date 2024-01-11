# vlc_-Media-Player-_history_shuffle-
Enhanced VLC shuffle specifically for VLC's "media player" functionality by leveraging historical play data to better randomize Media PLayer playlists

# History MediaPlayer Shuffle V1

## Overview
The `VLC - MediaPlayer History Shuffle.lua` VLC extension enhances the playlist shuffle functionality by utilizing historical play data. It intelligently curates the playlist by considering play counts, skip counts, and user-provided 'like' ratings.

## Features
1. **Data Structure**: The extension maintains a database of songs with attributes such as [playcount](file:///c%3A/Users/Sennacherib/Documents/vlc_shuffle%20extension%20CursorAi-proj/%60Changes%20in%20%60history_playlist_enhanced_v3.1.lua%60README.txt#29%2C53-29%2C53), [skipcount](file:///c%3A/Users/Sennacherib/Documents/vlc_shuffle%20extension%20CursorAi-proj/%60Changes%20in%20%60history_playlist_enhanced_v3.1.lua%60README.txt#29%2C66-29%2C66), [like](file:///c%3A/Users/Sennacherib/Documents/vlc_shuffle%20extension%20CursorAi-proj/%60Changes%20in%20%60history_playlist_enhanced_v3.1.lua%60README.txt#27%2C306-27%2C306), and `last played time`.

2. **Like Rating System**: A 'like' rating is calculated for each song, influencing its probability of being played in the shuffled playlist.

3. **Adaptive Shuffle**: The shuffle algorithm prioritizes songs with higher 'like' ratings, ensuring that preferred songs are played more often.

4. **Data Persistence**: Song data is stored in a CSV file, allowing the extension to remember user preferences across different sessions.

5. **Compatibility**: The extension is designed to work with VLC's media library, ensuring a seamless experience across different platforms.

## Installation
To install the extension, place the `VLC - MediaPlayer History Shuffle.lua.lua` file in the VLC extensions directory.

## Usage
Once installed, the extension can be accessed from the VLC menu under `View > History MediaPlayer Shuffle V1`. The shuffle will automatically take into account historical data when activated.

## Contributing
Contributions to `VLC - MediaPlayer History Shuffle.lua` are welcome. Please feel free to submit pull requests or create issues for bugs and feature requests.

## License
This project is licensed under the MIT License - see the LICENSE file for details.