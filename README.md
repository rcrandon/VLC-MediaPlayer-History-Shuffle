# VLC - MediaPlayer History Shuffle
Enhanced VLC shuffle specifically for VLC's "media player" functionality by leveraging historical play data to better randomize Media PLayer playlists

# VLC - MediaPlayer History Shuffle

## Overview
The `VLC - MediaPlayer History Shuffle.lua` VLC extension enhances the playlist shuffle functionality by utilizing historical play data. It intelligently curates the playlist by considering play counts, skip counts, and user-provided 'like' ratings.

## Features
1. **Like Rating System**: A 'like' rating is calculated for each song, influencing its probability of being played in the shuffled playlist.

2. **Adaptive Shuffle**: The shuffle algorithm prioritizes songs with higher 'like' ratings, ensuring that preferred songs are played more often.

3. **Data Persistence**: Song data is stored in a CSV file, allowing the extension to remember user preferences across different sessions.

4. **Compatibility**: The extension is designed to work with VLC's media library, ensuring a seamless experience across different platforms.

## Installation
To install the extension, place the `VLC - MediaPlayer History Shuffle.lua` file in the `%AppData%\vlc\lua\extensions` VLC extensions directory.

## Usage
Once installed, the extension can be accessed from the VLC menu under `View > VLC - MediaPlayer History Shuffle`. The shuffle will automatically take into account historical data when activated.

## Contributing
Contributions to `VLC - MediaPlayer History Shuffle.lua` are welcome. Please feel free to submit pull requests or create issues for bugs and feature requests.
