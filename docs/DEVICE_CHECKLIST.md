# Device acceptance checks

These checks need an actual Android phone and Windows PC. Unit/widget tests cannot establish hardware, notification permission, or OS-codec behavior.

1. Fresh install: complete or skip the guide; close/reopen and confirm it does not repeat. Replay it from Field guide.
2. Create tomorrow's Restaurant album; verify five photo ideas. Create Party and confirm the ideas change with the occasion.
3. Edit an idea, like another, and shuffle another. Close/reopen and verify edits, completion, and learned preference state persist.
4. Capture a photo. Deny camera access once and verify the app offers a useful error and retry. On Windows, enable desktop camera access in Windows Privacy settings; test a connected webcam and no-webcam state.
5. Attach a photo to an idea; verify it marks complete. Import an unrelated photo and a small MP4/H.264 video. View, zoom, play, pause, seek, and mute. Test a codec the OS cannot play and verify the error is understandable.
6. Add a photo/video comment, album note, and rating. Restart and confirm the media and text remain. Delete an app copy and confirm the original selected source file remains.
7. Set a reminder a few minutes ahead for a selected idea. Allow notifications, close the app, and verify it fires. Check Android battery optimizations and Windows Focus/Do Not Disturb if delayed. Replace the reminder and confirm only the new one fires; remove it and confirm cancellation. Test Android restart before a future reminder.
8. Deny notification permission and try setting another reminder. Verify the app reports the denied/unavailable state instead of claiming success.
9. Disconnect all network access. Create another album, shuffle, like, import, capture, play media, and restart. Suggestions and the journal should keep working.
10. On Windows resize the window; on Android use both portrait and landscape. Check the keyboard/dialog controls and large system text. Verify expected data loss warning before uninstalling; local storage is not cloud backup.

Development APK signing keys may differ between machines or CI runs. Do not uninstall an existing journal just to install a differently signed test build without first preserving original media and notes. Use one stable private signing key for releases and updates.
