# VLC - MediaPlayer History Shuffle
Enhanced VLC shuffle specifically for VLC's "media player" functionality by leveraging historical play data to better randomize Media PLayer playlists

# VLC - MediaPlayer History Shuffle

## Overview
The `VLC - MediaPlayer History Shuffle.lua` VLC extension enhances the playlist shuffle functionality by utilizing historical play data. It intelligently curates the playlist by considering play counts, skip counts, and user-provided 'like' ratings.

## Features
1. **Like Rating System**: A 'like' rating is calculated for each song based on play count, skip count, and user ratings, influencing its probability of being played in the shuffled playlist.

2. **Adaptive Shuffle**: The shuffle algorithm prioritizes songs with higher 'like' ratings, ensuring that preferred songs are played more often.

3. **Data Persistence**: Song data is stored in a JSON file with atomic writes to prevent corruption, allowing the extension to remember user preferences across different sessions.

4. **User Rating System**: Manually rate songs from 0-10 to influence their likelihood of being played.

5. **Export/Import**: Back up and restore your ratings data to/from external JSON files.

6. **Blacklist Feature**: Exclude songs from shuffle by blacklisting them (sets rating below threshold).

7. **Cross-Platform**: Works on Windows, Linux, and macOS with proper path handling.

8. **Robust Error Handling**: Atomic file writes and comprehensive error handling prevent data loss.

## Installation

### Windows
Place the `VLC - MediaPlayer History Shuffle.lua` file in:
```
%AppData%\vlc\lua\extensions
```

### Linux
Place the file in:
```
~/.local/share/vlc/lua/extensions/
```

### macOS
Place the file in:
```
~/Library/Application Support/vlc/lua/extensions/
```

## Usage
Once installed, the extension can be accessed from the VLC menu under `View > VLC - MediaPlayer History Shuffle`. The shuffle will automatically take into account historical data when activated.

### Menu Options
- **View Ratings**: Display all songs and their calculated like ratings
- **Set Rating for Current Song**: Manually rate the currently playing song (0-10)
- **Export Ratings Data**: Save your ratings database to an external JSON file
- **Import Ratings Data**: Load ratings from a previously exported JSON file
- **Blacklist Current Song**: Exclude the current song from future shuffles
- **View Blacklisted Songs**: See all songs that have been blacklisted

### How It Works
The extension calculates a "like" rating for each song based on:
- **Play count**: Each full play increases the rating
- **Skip count**: Each skip decreases the rating  
- **User rating**: Manual 0-10 ratings have the strongest influence
- **Blacklist threshold**: Songs below -50 rating are excluded from shuffle

The shuffle algorithm then uses weighted random selection, making higher-rated songs more likely to be played while still maintaining randomness.

## Contributing
Contributions to `VLC - MediaPlayer History Shuffle.lua` are welcome. Please feel free to submit pull requests or create issues for bugs and feature requests.
