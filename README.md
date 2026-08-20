# StayAwake

A tiny keep-awake utility for Windows, written as a single PowerShell script.
No install, no dependencies, no admin rights. It lives in the notification area:
as long as the icon is there, the session is being kept active.

## What it does

Two complementary mechanisms, because each one alone covers a different timer:

1. **Synthetic input.** Every N minutes it injects an `F15` key press through
   `SendInput()`. Windows decides that a user is idle by reading a counter that
   is reset by *any* system input event, which is what `GetLastInputInfo()`
   exposes. Injecting real input is therefore the only reliable way to reset it.
2. **Execution state.** It calls
   `SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)`,
   the declarative way of telling Windows that display and system must stay on.
   This blocks the power timers (relevant on battery), but it is not reliable on
   its own against everything, hence mechanism 1.

### Why F15

`VK_F15` (`0x7E`) exists in the keyboard layout but is on no modern physical
keyboard, so no application has ever bound a shortcut to it. A `Shift` press or
a mouse move would reset the same counter, but they can interfere with what you
are doing: modifier state, text selections, hover menus. F15 cannot.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (ships with Windows) or PowerShell 7
- No administrator rights

## Usage

```powershell
.\StayAwake.ps1                                  # default: every 10 minutes
.\StayAwake.ps1 -IntervalloMinuti 12             # custom interval
.\StayAwake.ps1 -IntervalloMinuti 10 -DurataOre 8  # stop by itself after 8 hours
.\StayAwake.ps1 -Console                         # keep the console visible (debug)
```

Or double click `Avvia StayAwake.cmd`, which passes any argument straight through.

| Parameter | Default | Meaning |
|---|---|---|
| `-IntervalloMinuti` | `10` | Minutes between injections (1 to 60) |
| `-DurataOre` | `0` | Hours after which it stops by itself. `0` means until you quit |
| `-Console` | off | Do not hide the console window, useful only for diagnostics |

`-DurataOre` is worth using: without it, a forgotten instance keeps the machine
awake and unlocked overnight.

## While it runs

The script hides its own console with `ShowWindow(GetConsoleWindow(), SW_HIDE)`
and runs a Win32 message loop (`Application.Run`), so it has no taskbar button.
The tray icon is the only indicator:

- **hover**: last and next injection time
- **right click**: status line, `Rinnova adesso` (inject now), `Esci` (quit)
- **double click**: inject now

> Windows 11 puts new tray icons in the hidden overflow area by default. To keep
> it visible, drag it out of the overflow, or enable it under
> Settings > Personalization > Taskbar > Other system tray icons.

**The menu and tooltips are in Italian.** The script is otherwise
self-explanatory; translating the UI strings is a matter of editing a handful of
literals near the bottom of the file.

## Verifying that it actually works

Do not trust "the API returned success". Watch the idle counter itself:

```powershell
Add-Type -Namespace Check -Name Idle -MemberDefinition @'
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")] private static extern uint GetTickCount();
    public static uint IdleMs()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return GetTickCount() - lii.dwTime;
    }
'@
1..10 | ForEach-Object { [Check.Idle]::IdleMs(); Start-Sleep -Seconds 2 }
```

Leave the machine alone and watch the number climb, then drop back to near zero
at each injection.

Note that the first injection happens a few seconds after launch: `Add-Type`
compiles the inline C# with `csc.exe` at every start. Sampling too early looks
like a failure when it is only a cold start.

## Notes

- The injected key press is real system input. It resets the idle timers of
  anything that reads them, including idle lock policies. On a machine managed by
  someone else, check what you are allowed to run.
- Pinning to the taskbar cannot be scripted on Windows 11: the shell verb was
  removed. `Add to Favorites` and `Add to Start` are still available.

## License

MIT, see [LICENSE](LICENSE).
