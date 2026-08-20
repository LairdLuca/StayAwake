<#
.SYNOPSIS
    Tiene attiva la sessione iniettando un input innocuo a intervalli regolari.
    Vive nell'area di notifica: finche' l'icona c'e', il tool sta lavorando.

.DESCRIPTION
    Due meccanismi complementari:
      1. SendInput() con il tasto F15 -> azzera il contatore di inattivita' che
         Windows usa per far partire lo screensaver.
      2. SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED) -> blocca
         i timer di spegnimento schermo e sospensione (rilevanti a batteria).

.PARAMETER IntervalloMinuti
    Ogni quanti minuti iniettare l'input. Default 10.

.PARAMETER DurataOre
    Dopo quante ore fermarsi da solo. 0 = fino a "Esci" dal menu dell'icona.

.PARAMETER Console
    Lascia visibile la finestra della console (utile solo per diagnosticare).

.EXAMPLE
    .\StayAwake.ps1
    .\StayAwake.ps1 -IntervalloMinuti 12 -DurataOre 8
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 60)]
    [int]$IntervalloMinuti = 10,

    [ValidateRange(0, 24)]
    [int]$DurataOre = 0,

    [switch]$Console
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -Namespace StayAwake -Name Native -MemberDefinition @'
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_F15 = 0x7E;

    private const uint ES_CONTINUOUS = 0x80000000;
    private const uint ES_DISPLAY_REQUIRED = 0x00000002;
    private const uint ES_SYSTEM_REQUIRED = 0x00000001;

    private const int SW_HIDE = 0;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("kernel32.dll")]
    private static extern uint GetTickCount();

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    // Inietta pressione e rilascio di F15: azzera il timer di inattivita'.
    public static uint Nudge()
    {
        INPUT[] inputs = new INPUT[2];

        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].U.ki.wVk = VK_F15;
        inputs[0].U.ki.dwFlags = 0;

        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].U.ki.wVk = VK_F15;
        inputs[1].U.ki.dwFlags = KEYEVENTF_KEYUP;

        return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    // Millisecondi trascorsi dall'ultimo input: serve a verificare l'effetto.
    public static uint InattivitaMs()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return GetTickCount() - lii.dwTime;
    }

    // Dichiara a Windows che schermo e sistema devono restare attivi.
    public static bool TieniAcceso()
    {
        return SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED) != 0;
    }

    // Rimuove la dichiarazione: i timer normali tornano validi.
    public static bool Rilascia()
    {
        return SetThreadExecutionState(ES_CONTINUOUS) != 0;
    }

    public static void NascondiConsole()
    {
        IntPtr h = GetConsoleWindow();
        if (h != IntPtr.Zero) { ShowWindow(h, SW_HIDE); }
    }
'@

if (-not $Console) { [StayAwake.Native]::NascondiConsole() }

# --- icona disegnata a runtime: cerchio pieno con anello bianco al centro ---
function New-IconaStato
{
    param([System.Drawing.Color]$Colore)

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $pennello = New-Object System.Drawing.SolidBrush $Colore
    $g.FillEllipse($pennello, 1, 1, 30, 30)

    $bianco = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.FillEllipse($bianco, 9, 9, 14, 14)
    $g.FillEllipse($pennello, 13, 13, 6, 6)

    $pennello.Dispose(); $bianco.Dispose(); $g.Dispose()

    $hIcon = $bmp.GetHicon()
    $icona = [System.Drawing.Icon]::FromHandle($hIcon)
    $bmp.Dispose()
    return $icona
}

$script:intervalloSecondi = $IntervalloMinuti * 60
$script:scadenza = if ($DurataOre -gt 0) { (Get-Date).AddHours($DurataOre) } else { $null }
$script:ultimo = $null
$script:conteggio = 0
$script:chiuso = $false

$script:iconaAttiva = New-IconaStato ([System.Drawing.Color]::FromArgb(46, 155, 78))

$script:notifica = New-Object System.Windows.Forms.NotifyIcon
$script:notifica.Icon = $script:iconaAttiva
$script:notifica.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:voceStato = $menu.Items.Add("Avvio in corso...")
$script:voceStato.Enabled = $false
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$voceOra = $menu.Items.Add("Rinnova adesso")
$voceEsci = $menu.Items.Add("Esci")

$script:notifica.ContextMenuStrip = $menu

$script:contesto = New-Object System.Windows.Forms.ApplicationContext

function Invoke-Rinnovo
{
    $inviati = [StayAwake.Native]::Nudge()
    $script:ultimo = Get-Date
    $script:conteggio++

    $prossimo = $script:ultimo.AddSeconds($script:intervalloSecondi)

    if ($inviati -eq 2)
    {
        # NotifyIcon.Text ha un limite di 63 caratteri: testo volutamente corto.
        $script:notifica.Text = "StayAwake attivo`nProssimo: {0}" -f $prossimo.ToString('HH:mm')
        $script:voceStato.Text = "Attivo - ultimo {0}, prossimo {1}" -f $script:ultimo.ToString('HH:mm'), $prossimo.ToString('HH:mm')
    }
    else
    {
        $script:notifica.Text = "StayAwake: input rifiutato"
        $script:voceStato.Text = "Errore: SendInput ha accettato $inviati eventi su 2"
    }
}

function Stop-StayAwake
{
    if ($script:chiuso) { return }
    $script:chiuso = $true
    $script:timer.Stop()
    [void][StayAwake.Native]::Rilascia()
    $script:notifica.Visible = $false
    $script:notifica.Dispose()
    $script:iconaAttiva.Dispose()
    $script:contesto.ExitThread()
}

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = $script:intervalloSecondi * 1000
$script:timer.Add_Tick({
    if ($script:scadenza -and (Get-Date) -ge $script:scadenza)
    {
        Stop-StayAwake
        return
    }
    Invoke-Rinnovo
})

$voceOra.Add_Click({ Invoke-Rinnovo })
$voceEsci.Add_Click({ Stop-StayAwake })
$script:notifica.Add_DoubleClick({ Invoke-Rinnovo })

if (-not [StayAwake.Native]::TieniAcceso())
{
    $script:notifica.ShowBalloonTip(5000, "StayAwake", "Attenzione: SetThreadExecutionState non ha risposto. Resta attiva la sola iniezione di input.", [System.Windows.Forms.ToolTipIcon]::Warning)
}

Invoke-Rinnovo
$script:timer.Start()

$messaggio = "Input ogni $IntervalloMinuti minuti."
if ($script:scadenza) { $messaggio += " Si ferma alle $($script:scadenza.ToString('HH:mm'))." }
$script:notifica.ShowBalloonTip(4000, "StayAwake attivo", $messaggio, [System.Windows.Forms.ToolTipIcon]::Info)

try
{
    [System.Windows.Forms.Application]::Run($script:contesto)
}
finally
{
    [void][StayAwake.Native]::Rilascia()
    if (-not $script:chiuso -and $script:notifica) { $script:notifica.Visible = $false; $script:notifica.Dispose() }
}
