# Restore-RecycleBin.ps1

A robust PowerShell script for silently restoring files from the Windows Recycle Bin to their original locations using robocopy.

## 🌟 Features

- **Silent Operation**: Uses robocopy instead of Shell.Application's Restore(), preventing GUI dialogs that freeze your system
- **Batch Processing**: Handles large Recycle Bins (18,000+ files) with efficient memory management
- **Flexible Restore Modes**:
  - Restore to original locations (default)
  - Restore to `\RecycleBin_Recovery\` folder with preserved directory structure
- **Multi-Drive Support**: Select which drives' Recycle Bins to process
- **What-If Simulation**: Test the first 100 files without making any changes
- **Background Execution**: Run as a background job or in foreground with progress
- **Optional Logging**: Detailed logs with timestamps and success/failure tracking
- **Interactive Dialog**: User-friendly menu for configuration (or use command-line parameters)

## 📋 Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges (required to access Recycle Bin)
- robocopy (built-in on Windows)

## 🚀 Quick Start

### Interactive Mode (Recommended for First Use)

```powershell
.\Restore-RecycleBin.ps1
```

This opens an interactive dialog where you can:
1. Select which drives to restore from
2. Configure logging options
3. Choose restore mode (original location vs. recovery folder)
4. Enable what-if simulation for testing
5. Select execution mode (foreground/background)

### Command-Line Mode

```powershell
# Restore all files from C: drive to original locations
.\Restore-RecycleBin.ps1 -NoDialog -Drives C

# Simulate first 100 files (no actual restore)
.\Restore-RecycleBin.ps1 -NoDialog -Drives C -WhatIfFirst100

# Restore to recovery folder with logging
.\Restore-RecycleBin.ps1 -NoDialog -Drives C -RestoreToRecovery -LogPath "C:\Temp\restore.log"

# Restore from multiple drives as background job
.\Restore-RecycleBin.ps1 -NoDialog -Drives C,D,E -Background -LogPath "C:\Temp\restore.log"
```

## 📖 Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Background` | Switch | Run restoration as a background job |
| `-LogPath` | String | Path to log file (enables logging if specified) |
| `-NoDialog` | Switch | Skip interactive dialog, use command-line parameters only |
| `-Drives` | Char[] | Specific drive letters to restore from (e.g., 'C','D') |
| `-RestoreToRecovery` | Switch | Restore to `\RecycleBin_Recovery\` instead of original locations |
| `-WhatIfFirst100` | Switch | Simulate first 100 files without making changes |

## 💡 Usage Examples

### Example 1: Test Before Restoring
```powershell
# First, simulate to see what would happen
.\Restore-RecycleBin.ps1 -NoDialog -Drives C -WhatIfFirst100 -LogPath "C:\Temp\test.log"

# Review the log file, then do the actual restore
.\Restore-RecycleBin.ps1 -NoDialog -Drives C -LogPath "C:\Temp\restore.log"
```

### Example 2: Safe Recovery to Separate Folder
```powershell
# Restore files to \RecycleBin_Recovery\ to review before moving to original locations
.\Restore-RecycleBin.ps1 -NoDialog -Drives C -RestoreToRecovery
```

### Example 3: Background Job for Large Restores
```powershell
# Start restoration as background job
$job = .\Restore-RecycleBin.ps1 -NoDialog -Drives C,D -Background -LogPath "C:\Temp\restore.log"

# Check job status
Get-Job $job.Id

# Get results when complete
Receive-Job $job.Id
```

## 🔧 How It Works

1. **Enumeration**: Uses `Shell.Application` COM object to access Recycle Bin metadata and retrieve original file paths
2. **Batch Processing**: Processes items in batches of 100 to prevent memory issues with large Recycle Bins
3. **Silent Copying**: Uses robocopy with silent flags (`/NP /NS /NC /NFL /NDL /NJH /NJS`) to copy files without GUI
4. **File Renaming**: Renames files from Recycle Bin's `$R*` format back to original names
5. **Stability**: Includes garbage collection and brief pauses between batches for system stability

## 📊 Performance

- **Small Recycle Bins** (< 1,000 files): Completes in seconds
- **Large Recycle Bins** (10,000+ files): Processes approximately 100 files every 30-60 seconds
- **Memory Efficient**: Batch processing prevents memory exhaustion with large datasets

## ⚠️ Important Notes

- **Administrator Rights**: The script requires administrator privileges to access `$RECYCLE.BIN` folders
- **Original Paths**: Files without retrievable original paths will fail to restore (logged as warnings)
- **Duplicate Names**: If a file already exists at the destination, robocopy will overwrite it
- **What-If Mode**: Only simulates the first 100 files for quick testing; actual restore processes all files

## 🐛 Troubleshooting

### "Access Denied" Errors
Run PowerShell as Administrator.

### "Original Path Unknown" Warnings
Some Recycle Bin items may have corrupted metadata. These files cannot be restored to original locations but can be restored to the recovery folder.

### Script Stops After Processing Some Files
- Check available disk space on destination drives
- Review the log file for specific error messages
- Try running with `-WhatIfFirst100` to test a smaller batch

### Background Job Shows No Output
Use `Receive-Job <JobId>` to retrieve output from background jobs.

## 📝 Changelog

### Version 3.3 (2025-12-08)
- Added batch processing for large Recycle Bins (100 items per batch)
- Implemented memory management with garbage collection between batches
- Added stability pauses between batches
- Improved logging with batch progress indicators

### Version 3.2 (2025-12-07)
- Fixed original path retrieval using Shell.Application COM
- Replaced filesystem-based metadata parsing with reliable COM approach
- Added file renaming from `$R*` format to original names

### Version 3.0 (2025-12-06)
- Complete rewrite using robocopy for silent operation
- Added multi-drive selection
- Added restore mode options (original vs. recovery folder)
- Added what-if simulation mode
- Added optional logging
- Added background job support

### Version 2.0 (Original)
- Used Shell.Application's Restore() method (caused GUI blocking)

## 📄 License

This script is provided as-is under the MIT License. See [LICENSE.txt](LICENSE.txt) for details.

## 👤 Author

Created by [DickHorner](https://gist.github.com/DickHorner/)

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/DickHorner/userscripts/issues).

## ⭐ Show Your Support

Give a ⭐️ if this project helped you!
