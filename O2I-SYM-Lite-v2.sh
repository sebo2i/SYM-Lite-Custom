#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# SYM-Lite
#
# - Lean, purpose-built script for executing approved software and management actions
# - User selects which items to install/execute via swiftDialog selection UI
# - Monitors execution progress via swiftDialog Inspect Mode
# - No user input prompts beyond selection (no asset tag, computer name, etc.)
#
# https://snelson.us/sym
#
####################################################################################################
#
# HISTORY
#
# Version 1.6.0, 10-Oct-2026, Dan K. Snelson (@dan-snelson)
# - When `git` is missing (no Xcode, Command Line Tools, or brewed `git`), SYM-Lite installs Apple's Command Line Tools as `root` via `softwareupdate` so Homebrew isn't left degraded; logic adapted from Rich Trouton's `install_xcode_command_line_tools.sh`; disable with `homebrewAutoInstallCommandLineTools="false"` (Issue #27)
# - Command Line Tools install runs once per run, before the Installomator `homebrew` label installs Homebrew (Homebrew.pkg's postinstall resets its `git` checkout only when Command Line Tools `git` exists; otherwise `brew --version` reports `-dirty`), after the label skips an existing Homebrew, and before the first Homebrew item; it needs no logged-in user
# - Pre-flight logs whether `git` is available for Homebrew
# - With `homebrewUpdateBeforeInstall="true"`, a still-missing `git` skips `brew update` with one `[WARNING]` instead of failing every Homebrew item
# - The Installomator `homebrew` completion row adds "git is missing, so brew update is unavailable" when Command Line Tools couldn't be installed
# - Inspect Mode shows a "Command Line Tools (for Homebrew)" row where the install runs (before the `homebrew` label or the first Homebrew item); it completes once `git` is available, and its side message leads the list (Preset 3 shows only the first side message) noting it can take several minutes with no visible progress
# - After the Installomator `homebrew` label (or a Command Line Tools install), `brew --version` is logged once per run; a `-dirty` checkout logs a `[WARNING]` suggesting `brew update-reset`
# - Command Line Tools progress is logged: `softwareupdate` scan and install output stream to the log as `softwareupdate (CLT scan): …` and `softwareupdate (CLT): …`, with elapsed seconds for each step
# - Selection and completion dialog height is now Parameter 6 (default: `675`), so a short `operationsCSV` list can use a smaller window
# - When Parameter 6 is less than `500`, Inspect Mode uses Preset 3 (Compact) instead of `organizationPreset`, sized to match the selection and completion dialogs (900 x Parameter 6)
# - Inspect Mode's completion button reads "Continue" (was "Review Results"); Preset 3 omits "Please wait..." because it ignores `autoEnableButtonText` when `button1text` is set
# - Installomator `codex` validation path is now `/Applications/ChatGPT.app` (where the label installs), so Inspect Mode marks it complete and enables the button
# - Added Installomator labels: Oracle MySQL Workbench CE (`mysqlworkbenchce`), OutSystems Service Studio (`outsystemsservicestudio`)
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
setopt NONOMATCH
setopt TYPESET_SILENT

# Script Version
scriptVersion="1.6.0"

# Script Human-readable Name
humanReadableScriptName="O2i Ingénierie : Déploiement de poste"

# Organization's Script Name
organizationScriptName="O2I_Ingenierie"

# Client-side Log
scriptLog="/var/log/SYM-Lite-O2I.log"

# Installomator Log
installomatorLog="/var/log/Installomator.log"

# Elapsed Time
SECONDS="0"

# Minimum Required Version of swiftDialog
swiftDialogMinimumRequiredVersion="3.1.0.4994"

# Load is-at-least for version comparison
autoload -Uz is-at-least

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Variables portant sur les étapes ajoutées par O2I
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Variables Phase 1 : Message de bienvenue

# Contenu du message dans la fenêtre de bienvenue
messageWelcomeStep="**Bonjour et bienvenue !**\n\nCet assistant de déploiement va vous accompagner dans la configuration de votre poste.\n\nDans un premier temps, il vous sera demandé de remplir un formulaire (nom du poste et service d'appartenance).\n\nDans un second temps, vous pourrez séléctionner les Apps à installer sur votre poste.\n\nSelon votre séléction, le déploiement du poste prendra plus ou moins de temps (entre 10 à 30 minutes)."

# Variables Phase 2 : Nommage du poste

# Contenu du message dans la fenêtre nommage du poste
messageComputerNameStep="**Nommage du poste et séléction du service !**\n\nVeuillez remplir le formulaire ci-dessous.\n\n1- Saisissez le nom à donner au poste.\n\n2- Séléctionnez votre service d'appartenance.\n\n**NOTE :** Le nom de l'ordinateur peut contenir des majuscules, minuscules, chiffres, tirets et peut faire jusqu'à 15 caractères maximum (les autres caractères et les espaces sont interdits)."

# Nom du poste (extrait du formulaire, à remplir avant les installations)
computerName=""

# Forcer le changement de nom de l'ordinateur, même en mode silencieux (par défaut : false)
forceComputerNameInSilentMode="false"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Fin des variables portant sur les étapes ajoutées par O2I
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Runtime Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Runtime inputs (Jamf parameters by default; CLI flags can override)
operationMode="${4:-"interactive"}"     # Parameter 4: Operation Mode [ interactive (default) | silent ]
operationMode="${operationMode:l}"
operationsCSV="${5:-""}"                # Parameter 5: Comma-separated list of item IDs (silent: items to run; interactive: optional selection dialog allowlist)
dialogHeight="${6:-"675"}"              # Parameter 6: Selection and completion dialog height, in pixels (default: 675)



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Organization's swiftDialog Inspect Mode Preset Option (See: https://swiftdialog.app/advanced/inspect-mode/)
organizationPreset="2"

# Organization's Installomator Path
organizationInstallomatorFile="/usr/local/Installomator/Installomator.sh"

# Organization's Jamf Binary Path
jamfBinary="/usr/local/jamf/bin/jamf"

# Optional Homebrew binary override (otherwise /opt/homebrew/bin/brew, then /usr/local/bin/brew)
brewPath=""

# Enable or disable Jamf policy items
enableJamfPolicyItems="false"

# Enable or disable Homebrew package items
enableHomebrewItems="true"

# Update Homebrew metadata once before the first Homebrew package install
homebrewUpdateBeforeInstall="true"

# Create zsh and fish completion directories under the brew prefix (as the Homebrew user) before the first Homebrew install
homebrewCreateCompletionDirectories="true"

# Install Apple's Command Line Tools (as root, via softwareupdate) when git is missing, so Homebrew isn't degraded
homebrewAutoInstallCommandLineTools="true"

# Trust configured third-party tap items (`user/tap/name`) before install; official taps are always trusted
homebrewAutoTrustItems="true"

# Remove Apple's quarantine flag from installed Homebrew cask apps (only when Gatekeeper accepts the app)
homebrewAutoRemoveQuarantine="true"

# Organization's Overlayicon URL
organizationOverlayiconURL="SF=gearshape.2,colour=pink,colour2=purple"

# Main Dialog Icon
mainDialogIcon="https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Companies/icone-O2iIng-512%C3%97512.png"

# Dialog presentation defaults
fontSize="14"
selectionDialogDefaultChecked="true"
selectionDialogStatusSublabelsEnabled="true"

# Restart prompt behavior
restartPromptEnabled="true"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Item Configuration Arrays
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Homebrew prefix for validation paths (`hw.optional.arm64` reads 1 on Apple silicon, even under Rosetta)
if [[ "$( /usr/sbin/sysctl -in hw.optional.arm64 )" == "1" ]]; then
    homebrewPrefix="/opt/homebrew"
else
    homebrewPrefix="/usr/local"
fi

# Installomator Labels
# Format: "label | Display Name | Validation Path | Icon URL"
installomatorLabels=(
    "adobeacrobatprodc | Adobe Acrobat Pro DC | /Applications/Adobe Acrobat DC/Adobe Acrobat.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Acrobat%20Reader%20DC.png"
    "adobereaderdc | Adobe Acrobat DC | /Applications/Adobe Acrobat DC/Adobe Acrobat.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Acrobat%20Reader%20DC.png"
    "amazoncorretto25jdk | Amazon Corretto 25 JDK | /Library/Java/JavaVirtualMachines/amazon-corretto-25.jdk/Contents/Home/bin/java | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Amazon%20Corretto%20JDK.png"
    "anydesk | AnyDesk | /Applications/AnyDesk.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/AnyDesk.png"
    "apachedirectorystudio | Apache Directory Studio | /Applications/ApacheDirectoryStudio.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/ApacheDirectoryStudio.png"
    "apparency | Apparency | /Applications/Apparency.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Apparency.png"
    "appcleaner | AppCleaner | /Applications/AppCleaner.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/AppCleaner.png"
    "autopkgr | AutoPkgr | /Applications/AutoPkgr.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/AutoPkgr.png"
    "balenaetcher | balenaEtcher | /Applications/balenaEtcher.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/balenaEtcher.png"
    "bbedit | BBEdit | /Applications/BBEdit.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/BBEdit.png"
    "bitwarden | Bitwarden | /Applications/Bitwarden.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Bitwarden.png"
    "blender | Blender | /Applications/Blender.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Blender.png"
    "boxdrive | Box | /Applications/Box.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Box.png"
    "brave | Brave Browser | /Applications/Brave Browser.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Brave%20Browser.png"
    "carboncopycloner | Carbon Copy Cloner | /Applications/Carbon Copy Cloner.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Carbon%20Copy%20Cloner.png"
    "catoclient | CatoClient | /Applications/CatoClient.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/CatoClient.png"
    "claudedesktop | Claude AI | /Applications/Claude.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Claude.png"
    "clickshare | ClickShare | /Applications/ClickShare.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/ClickShare.png"
    "coconutbattery | coconutBattery | /Applications/coconutBattery.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/coconutBattery.png"
    "crystalfetch | CrystalFetch | /Applications/CrystalFetch.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/CrystalFetch.png"
    "cyberduck | Cyberduck | /Applications/Cyberduck.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Cyberduck.png"
    "deepl | DeepL | /Applications/DeepL.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/DeepL.png"
    "deezer | Deezer | /Applications/Deezer.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Deezer.png"
    "displaylinkmanager | DisplayLink Manager | /Applications/DisplayLink Manager.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/DisplayLink%20Manager.png"
    "drawio | draw.io | /Applications/draw.io.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/draw.io.png"
    "dropbox | Dropbox | /Applications/Dropbox.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Dropbox.png"
    "firefox | Firefox | /Applications/Firefox.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Firefox.png"
    "gimp | GIMP | /Applications/GIMP.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/GIMP.png"
    "githubdesktop | GitHub Desktop | /Applications/GitHub Desktop.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/GitHub%20Desktop.png"
    "googlechrome | Google Chrome | /Applications/Google Chrome.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Google%20Chrome.png"
    "handbrake | HandBrake | /Applications/HandBrake.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/HandBrake.png"
    "homebrew | Homebrew | ${homebrewPrefix}/bin/brew | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/homebrew.png"
    "ice | Ice | /Applications/Ice.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Ice.png"
    "imazingprofileeditor | iMazing Profile Editor | /Applications/iMazing Profile Editor.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/iMazing%20Profile%20Editor.png"
    "inkscape | Inkscape | /Applications/Inkscape.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Inkscape.png"
    "jamfconnectconfiguration | Jamf Connect Configuration | /Applications/Jamf Connect Configuration.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Jamf%20Connect%20Configuration.png"
    "jamfprintermanager | Jamf Printer Manager | /Applications/Jamf Printer Manager.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Jamf%20Printer%20Manager.png"
    "jamfpppcutility | Jamf PPPC Utility | /Applications/PPPC Utility.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/PPPC%20Utility.png"
    "jamfmigrator | Jamf Replicator | /Applications/Replicator.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Replicator.png"
    "jamfcheck | JamfCheck | /Applications/JamfCheck.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/JamfCheck.png"
    "jamfcpr | jamfcpr | /Applications/jamfcpr.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/jamfcpr.png"
    "keepassxc | KeePassXC | /Applications/KeePassXC.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/KeePassXC.png"
    "keka | Keka | /Applications/Keka.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Keka.png"
    "keystoreexplorer | KeyStore Explorer | /Applications/KeyStore Explorer.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/KeyStore%20Explorer.png"
    "krita | krita | /Applications/krita.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/krita.png"
    "libreoffice | LibreOffice | /Applications/LibreOffice.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/LibreOffice.png"
    "libreofficelanguagepackintl | LibreOffice Language Kit | /Applications/LibreOffice.app/Contents/Resources/resource/fr/LC_MESSAGES/avmedia.mo | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/LibreOffice.png"
    "logitechoptionsplus | Logi Options+ | /Applications/logioptionsplus.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/logioptionsplus.png"
    "mactracker | Mactracker | /Applications/Mactracker.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Mactracker.png"
    "malwarebytes | Malwarebytes | /Applications/Malwarebytes.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Malwarebytes.png"
    "microsoftazurestorageexplorer | Microsoft Azure Storage Explorer | /Applications/Microsoft Azure Storage Explorer.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Microsoft%20Azure%20Storage%20Explorer.png"
    "microsoftedge | Microsoft Edge | /Applications/Microsoft Edge.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Microsoft%20Edge.png"
    "microsoftofficebusinesspro | Microsoft Office Business Pro 365 | /Applications/Microsoft Word.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Microsoft%20Office-v2.png"
    "mist | Mist | /Applications/Mist.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Mist.png"
    "netspot | NetSpot | /Applications/NetSpot.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/NetSpot.png"
    "ollama | Ollama | /Applications/Ollama.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Ollama.png"
    "onyx | OnyX | /Applications/OnyX.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/OnyX.png"
    "openvpnconnectv3 | OpenVPN Connect | /Applications/OpenVPN Connect/OpenVPN Connect.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/OpenVPN%20Connect.png"
    "opera | Opera | /Applications/Opera.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Opera.png"
    "packages | Packages | /Applications/Packages.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Packages.png"
    "paretosecurity | Pareto Security | /Applications/Pareto Security.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Pareto%20Security.png"
    "pingplotter | PingPlotter | /Applications/PingPlotter.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/PingPlotter.png"
    "postman | Postman | /Applications/Postman.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Postman.png"
    "powermonitor | Power Monitor | /Applications/Power Monitor.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Power%20Monitor.png"
    "microsoftpowershell | Microsoft PowerShell | /Applications/PowerShell.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/PowerShell.png"
    "privileges2 | Privileges | /Applications/Privileges.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Privileges.png"
    "protonvpn | ProtonVPN | /Applications/ProtonVPN.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/ProtonVPN.png"
    "prune | Prune | /Applications/Prune.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Prune.png"
    "jamfreenroller | Jamf ReEnroller | /Applications/ReEnroller.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/ReEnroller.png"
    "rustdesk | RustDesk | /Applications/RustDesk.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/RustDesk.png"
    "scribus | Scribus | /Applications/Scribus.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Scribus.png"
    "shottr | Shottr | /Applications/Shottr.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Shottr.png"
    "signal | Signal | /Applications/Signal.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Signal.png"
    "slack | Slack | /Applications/Slack.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Slack.png"
    "sourcetree | Sourcetree | /Applications/Sourcetree.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Sourcetree.png"
    "spotify | Spotify | /Applications/Spotify.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Spotify.png"
    "supportapp | Support App | /Applications/Support.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Support.png"
    "suspiciouspackage | Suspicious Package | /Applications/Suspicious Package.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Suspicious%20Package.png"
    "synologydriveclient | Synology Drive Client | /Applications/Synology Drive Client.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Synology%20Drive%20Client.png"
    "synologyassistant | SynologyAssistant | /Applications/SynologyAssistant.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/SynologyAssistant.png"
    "teamviewer | TeamViewer | /Applications/TeamViewer.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/TeamViewer.png"
    "telegram | Telegram | /Applications/Telegram.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Telegram.png"
    "thunderbird_intl | Thunderbird | /Applications/Thunderbird.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Thunderbird.png"
    "toggltrack | Toggl Track | /Applications/Toggl Track.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Toggl%20Track.png"
    "tunnelblick | Tunnelblick | /Applications/Tunnelblick.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Tunnelblick.png"
    "microsoftvisualstudiocode | Visual Studio Code | /Applications/Visual Studio Code.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Visual%20Studio%20Code.png"
    "vivaldi | Vivaldi | /Applications/Vivaldi.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Vivaldi.png"
    "vlc | VLC | /Applications/VLC.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/VLC.png"
    "webex | Webex | /Applications/Webex.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Webex.png"
    "wechat | WeChat | /Applications/WeChat.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/WeChat.png"
    "whatsapp | WhatsApp | /Applications/WhatsApp.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/WhatsApp.png"
    "microsoftwindowsapp | Windows App | /Applications/Windows App.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Windows%20App.png"
    "wireshark | Wireshark | /Applications/Wireshark.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Wireshark.png"
    "zoomclient | zoom.us | /Applications/zoom.us.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/zoom.us.png"
)

configuredInstallomatorLabels=("${installomatorLabels[@]}")

# Jamf Pro Policies
# Format: "trigger | Display Name | Validation Path | Icon URL"
jamfPolicyItems=(
)

configuredJamfPolicyItems=("${jamfPolicyItems[@]}")

# Homebrew Items
# Format: "cask:token | Display Name | Validation Path | Icon URL"
homebrewItems=(
    "cask:artcraft-launcher | ArtCraft Launcher | /Applications/ArtCraft Launcher.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/ArtCraft%20Launcher.png"
    "cask:photocraft | PhotoCraft | /Applications/PhotoCraft.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/PhotoCraft.png"
    "cask:avast-security | Avast Security | /Applications/Avast.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Avast%20Security.png"
    "cask:ccleaner | CCleaner | /Applications/CCleaner.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/CCleaner.png"
    "cask:cisco-jabber | Cisco Jabber | /Applications/Cisco Jabber.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Cisco%20Jabber.png"
    "cask:combine-pdfs | Combine PDFs | /Applications/Combine PDFs.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Combine%20PDFs.png"
    "cask:freefilesync | FreeFileSync | /Applications/FreeFileSync.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/FreeFileSync.png"
    "cask:ganttproject | GanttProject | /Applications/GanttProject.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/GanttProject.png"
    "cask:image2icon | Image2Icon | /Applications/Image2Icon.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Image2Icon.png"
    "cask:librewolf | LibreWolf | /Applications/LibreOffice.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/LibreWolf.png"
    "cask:mds | MDS | /Applications/MDS.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/MDS.png"
    "cask:megasync | MEGAsync | /Applications/MEGAsync.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/MEGAsync.png"
    "cask:bing-wallpaper | Microsoft Bing Wallpaper | /Applications/Microsoft Bing Wallpaper.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Microsoft%20Bing%20Wallpaper.png"
    "cask:mullvad-browser | Mullvad Browser | /Applications/Mullvad Browser.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Mullvad%20Browser.png"
    "cask:namechanger | NameChanger | /Applications/NameChanger.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/NameChanger.png"
    "cask:opera-air | Opera Air | /Applications/Opera Air.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Opera%20Air.png"
    "cask:pdf-squeezer | PDF Squeezer | /Applications/PDF Squeezer.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/PDF%20Squeezer.png"
    "cask:qfinder-pro | Qfinder Pro | /Applications/Qfinder Pro.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Qfinder%20Pro.png"
    "cask:serial | Serial | /Applications/Serial.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Serial.png"
    "cask:supportcompanion | SupportCompanion | /Applications/SupportCompanion.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/SupportCompanion.png"
    "cask:termius | Termius | /Applications/Termius.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Termius.png"
    "cask:transmission | Transmission | /Applications/Transmission.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/Transmission.png"
    "cask:unifi-identity-endpoint | UniFi Endpoint | /Applications/UniFi Endpoint.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/UniFi%20Endpoint.png"
    "cask:vitalsource-bookshelf | VitalSource Bookshelf | /Applications/VitalSource Bookshelf.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/VitalSource%20Bookshelf.png"
    "cask:wifiman | WiFiman Desktop | /Applications/WiFiman Desktop.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/WiFiman%20Desktop.png"
    "cask:wpsoffice | WPS Office | /Applications/wpsoffice.app | https://raw.githubusercontent.com/sebo2i/icons/refs/heads/main/wpsoffice.png"
)

configuredHomebrewItems=("${homebrewItems[@]}")


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# swiftDialog Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# swiftDialog App Bundle
dialogAppBundle="/Library/Application Support/Dialog/Dialog.app"

# swiftDialog Binary Path (root-owned app bundle path; avoids /usr/local/bin, which may be user-owned on Intel Homebrew Macs)
dialogBinary="${dialogAppBundle}/Contents/MacOS/dialogcli"

# swiftDialog Runtime Directory (root-owned, 755; holds user hand-off files so they can't be swapped)
dialogRuntimeDirectory=""

# swiftDialog Inspect Mode JSON File
dialogInspectModeJSONFile=""

# swiftDialog Command File
dialogCommandFile=""



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Runtime Tracking Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

selectedItems=()
selectedInstallomatorLabels=()
selectedJamfPolicies=()
selectedHomebrewItems=()
failedItems=()
completedItems=()
skippedItems=()
completionReportRecords=()
completionDialogJSONFile=""
dialogPID=""
dialogTemporaryDirectory=""
selectionDialogOptionRecords=()
selectionDialogAllowedItemIDs=()
selectionDialogTotalItemCount=0
selectionDialogDisabledItemCount=0
selectionDialogCheckboxesJSON=""
effectiveBrewPath=""
homebrewUpdateAttempted="false"
homebrewUpdateSucceeded="false"
homebrewCompletionDirectoriesAttempted="false"
homebrewGitPath=""
commandLineToolsAttempted="false"
commandLineToolsTriggerFile="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
commandLineToolsTriggerFileCreated="false"
commandLineToolsInspectMarkerFile=""
homebrewVersionLogged="false"
homebrewCommandEnvironment=()
loggedInUserIsAdmin=""
homebrewExecutionUser=""



####################################################################################################
#
# Logging Helpers
#
####################################################################################################

function updateScriptLog() {
    local level="$1"
    local message="$2"
    echo "${organizationScriptName} (${scriptVersion}): $(date '+%Y-%m-%d %H:%M:%S')  [${level}] ${message}" | tee -a "${scriptLog}" >&2
}

function preFlight()    { updateScriptLog "PRE-FLIGHT" "${1}"; }
function logComment()   { updateScriptLog "INFO" "${1}"; }
function notice()       { updateScriptLog "NOTICE" "${1}"; }
function info()         { updateScriptLog "INFO" "${1}"; }
function warning()      { updateScriptLog "WARNING" "${1}"; }
function errorOut()     { updateScriptLog "ERROR" "${1}"; }
function fatal()        { updateScriptLog "FATAL ERROR" "${1}"; exit 10; }

function cleanup() {
    if [[ -n "${dialogInspectModeJSONFile}" && -e "${dialogInspectModeJSONFile}" ]]; then
        rm -f -- "${dialogInspectModeJSONFile}" 2>/dev/null
        dialogInspectModeJSONFile=""
    fi

    removeDialogCommandFile

    # Remove the Command Line Tools trigger file only if SYM-Lite created it
    if [[ "${commandLineToolsTriggerFileCreated}" == "true" ]]; then
        rm -f -- "${commandLineToolsTriggerFile}" 2>/dev/null
        commandLineToolsTriggerFileCreated="false"
    fi

    if [[ -n "${completionDialogJSONFile}" && -e "${completionDialogJSONFile}" ]]; then
        rm -f -- "${completionDialogJSONFile}" 2>/dev/null
        completionDialogJSONFile=""
    fi

    if [[ -n "${dialogTemporaryDirectory}" && -d "${dialogTemporaryDirectory}" ]]; then
        case "${dialogTemporaryDirectory}" in
            /tmp/*|/var/tmp/*|/private/tmp/*)
                rm -rf -- "${dialogTemporaryDirectory}" 2>/dev/null
                ;;
        esac
    fi

    if [[ -n "${dialogRuntimeDirectory}" && -d "${dialogRuntimeDirectory}" ]]; then
        case "${dialogRuntimeDirectory}" in
            /tmp/*|/var/tmp/*|/private/tmp/*)
                rm -rf -- "${dialogRuntimeDirectory}" 2>/dev/null
                dialogRuntimeDirectory=""
                ;;
        esac
    fi
}
trap cleanup EXIT



####################################################################################################
#
# Core Helper Functions
#
####################################################################################################

function currentLoggedInUser() {
    local shouldLog="${1:-true}"

    loggedInUser=$( /bin/echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ { print $3 }' )

    if [[ "${shouldLog}" == "true" ]]; then
        preFlight "Utilisateur actuellement connecté : ${loggedInUser}"
    fi
}

function updateLoggedInUserDetails() {
    loggedInUserFullname=$( /usr/bin/id -F "${loggedInUser}" )
    loggedInUserFirstname=$( /bin/echo "${loggedInUserFullname}" | /usr/bin/sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | /usr/bin/sed 's/\(.\{25\}\).*/\1…/' | /usr/bin/awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
    loggedInUserID=$( /usr/bin/id -u "${loggedInUser}" )
    loggedInUserHomeDirectory=$( /usr/bin/dscl -plist . read "/Users/${loggedInUser}" NFSHomeDirectory 2>/dev/null | /usr/bin/plutil -extract "dsAttrTypeStandard:NFSHomeDirectory.0" raw -o - - 2>/dev/null )
}

function isSystemConsoleUser() {
    case "$1" in
        ""|loginwindow|_mbsetupuser|root ) return 0 ;;
        * ) return 1 ;;
    esac
}

function requireLoggedInUser() {
    local context="${1:-perform a UI action}"

    currentLoggedInUser "false"

    if isSystemConsoleUser "${loggedInUser}"; then
        fatal "Aucun utilisateur connecté et valide n'a été détecté ; impossible de ${context}."
    fi

    if ! /usr/bin/id -u "${loggedInUser}" >/dev/null 2>&1; then
        fatal "Utilisateur connecté '${loggedInUser}' ne peut pas être résolu ; impossible de ${context}."
    fi

    updateLoggedInUserDetails
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Run command as logged-in user (thanks, @scriptingosx!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function runAsUser() {
    local user="$1"
    shift
    local userID=""

    if [[ -z "${user}" ]]; then
        "$@"
        return $?
    fi

    userID="$(id -u "${user}" 2>/dev/null)"
    if [[ "${userID}" =~ ^[0-9]+$ ]]; then
        /bin/launchctl asuser "${userID}" /usr/bin/sudo -u "${user}" "$@"
        return $?
    fi

    /usr/bin/sudo -u "${user}" "$@"
}

function launchAsUserInBackground() {
    local user="$1"
    shift
    local userID=""

    if [[ -z "${user}" ]]; then
        "$@" &
        dialogPID=$!
        return 0
    fi

    userID="$(id -u "${user}" 2>/dev/null)"
    if [[ ! "${userID}" =~ ^[0-9]+$ ]]; then
        errorOut "Impossible de résoudre l'ID utilisateur pour '${user}' lors du lancement du processus en arrière-plan"
        return 1
    fi

    /bin/launchctl asuser "${userID}" /usr/bin/sudo -u "${user}" "$@" &
    dialogPID=$!
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse Installomator Item Configuration
# Input: "label | displayName | validationPath | iconURL"
# Output: Sets global variables itemLabel, itemDisplayName, itemValidationPath, itemIconURL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseInstallomatorItem() {
    local itemConfig="$1"
    local parts=("${(@s: | :)itemConfig}")

    itemLabel="${parts[1]}"
    itemDisplayName="${parts[2]}"
    itemValidationPath="${parts[3]}"
    itemIconURL="${parts[4]}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse Jamf Policy Item Configuration
# Input: "trigger | displayName | validationPath | iconURL"
# Output: Sets global variables itemTrigger, itemDisplayName, itemValidationPath, itemIconURL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseJamfPolicyItem() {
    local itemConfig="$1"
    local parts=("${(@s: | :)itemConfig}")

    itemTrigger="${parts[1]}"
    itemDisplayName="${parts[2]}"
    itemValidationPath="${parts[3]}"
    itemIconURL="${parts[4]}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse Homebrew Item Configuration
# Input: "cask:token | displayName | validationPath | iconURL"
# Output: Sets global variables itemHomebrewID, itemBrewMode, itemBrewToken, itemDisplayName, itemValidationPath, itemIconURL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseHomebrewItem() {
    local itemConfig="$1"
    local parts=("${(@s: | :)itemConfig}")

    itemHomebrewID="${parts[1]}"
    itemBrewMode="${itemHomebrewID%%:*}"
    itemBrewToken="${itemHomebrewID#*:}"
    itemDisplayName="${parts[2]}"
    itemValidationPath="$(resolveHomebrewValidationPath "${parts[3]}")"
    itemIconURL="${parts[4]}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Resolve Homebrew Validation Path
# Input: Configured validation path
# Output: Effective validation path on stdout; `/Applications/…` paths also match `~/Applications/…`,
#         which is where casks install for non-admin users
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function resolveHomebrewValidationPath() {
    local validationPath="$1"
    local userValidationPath=""

    if [[ "${validationPath}" != /Applications/* || -z "${loggedInUserHomeDirectory}" ]]; then
        print -r -- "${validationPath}"
        return 0
    fi

    userValidationPath="${loggedInUserHomeDirectory}${validationPath}"

    if [[ -e "${validationPath}" ]]; then
        print -r -- "${validationPath}"
    elif [[ -e "${userValidationPath}" || "${loggedInUserIsAdmin}" == "false" ]]; then
        print -r -- "${userValidationPath}"
    else
        print -r -- "${validationPath}"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get Selection Dialog Status Text
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getSelectionDialogStatusText() {
    local validationPath="$1"

    if isValidationPathPresent "${validationPath}"; then
        print -r -- "Déjà installé"
    else
        print -r -- "Nouvelle installation"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get Selection Dialog Label
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getSelectionDialogLabel() {
    local displayName="$1"
    local validationPath="$2"
    local itemStatusText=""

    if [[ "${selectionDialogStatusSublabelsEnabled:l}" == "true" ]]; then
        itemStatusText=$(getSelectionDialogStatusText "${validationPath}")
        print -r -- "${displayName}"$'\n'"${itemStatusText}"
    else
        print -r -- "${displayName}"
    fi
}

function getSelectionDialogCheckboxesJSON() {
    local -a allSortKeys=()
    local -a usedCheckboxLabels=()
    local item=""
    local entry=""
    local checkboxItemsJSON=""
    local separator=""
    local checkboxLabel=""
    local escapedCheckboxLabel=""
    local escapedIconURL=""
    local checkboxChecked="false"
    local checkboxDisabled="false"
    local itemID=""
    local existingLabel=""
    local escapedItemID=""
    local -A allowedItemIDMap=()

    selectionDialogOptionRecords=()
    selectionDialogTotalItemCount=0
    selectionDialogDisabledItemCount=0

    # Optional allowlist from operationsCSV (interactive mode); empty shows all items
    for itemID in "${selectionDialogAllowedItemIDs[@]}"; do
        allowedItemIDMap[${itemID}]=1
    done

    for item in "${installomatorLabels[@]}"; do
        local parts=("${(@s: | :)item}")
        [[ ${#allowedItemIDMap} -gt 0 && -z "${allowedItemIDMap[${parts[1]}]}" ]] && continue
        allSortKeys+=("${parts[2]} | installomator | ${item}")
    done
    for item in "${jamfPolicyItems[@]}"; do
        local parts=("${(@s: | :)item}")
        [[ ${#allowedItemIDMap} -gt 0 && -z "${allowedItemIDMap[${parts[1]}]}" ]] && continue
        allSortKeys+=("${parts[2]} | jamf | ${item}")
    done
    for item in "${homebrewItems[@]}"; do
        local parts=("${(@s: | :)item}")
        [[ ${#allowedItemIDMap} -gt 0 && -z "${allowedItemIDMap[${parts[1]}]}" ]] && continue
        allSortKeys+=("${parts[2]} | homebrew | ${item}")
    done

    for entry in "${(oi)allSortKeys[@]}"; do
        ((selectionDialogTotalItemCount++))
        local entryParts=("${(@s: | :)entry}")
        local itemType="${entryParts[2]}"
        local itemConfig="${(j: | :)entryParts[3,-1]}"

        if [[ "${itemType}" == "installomator" ]]; then
            parseInstallomatorItem "${itemConfig}"
            itemID="${itemLabel}"
        elif [[ "${itemType}" == "jamf" ]]; then
            parseJamfPolicyItem "${itemConfig}"
            itemID="${itemTrigger}"
        else
            parseHomebrewItem "${itemConfig}"
            itemID="${itemHomebrewID}"
        fi

        checkboxLabel=$(getSelectionDialogLabel "${itemDisplayName}" "${itemValidationPath}")
        for existingLabel in "${usedCheckboxLabels[@]}"; do
            if [[ "${existingLabel}" == "${checkboxLabel}" ]]; then
                checkboxLabel="${checkboxLabel} (${itemID})"
                break
            fi
        done
        usedCheckboxLabels+=("${checkboxLabel}")

        if [[ "${selectionDialogStatusSublabelsEnabled:l}" == "true" ]] && isValidationPathPresent "${itemValidationPath}"; then
            checkboxDisabled="true"
            ((selectionDialogDisabledItemCount++))
        else
            checkboxDisabled="false"
            selectionDialogOptionRecords+=("${itemID}")
        fi

        if [[ "${selectionDialogDefaultChecked:l}" == "true" ]] && [[ "${checkboxDisabled}" == "false" ]]; then
            checkboxChecked="true"
        else
            checkboxChecked="false"
        fi

        escapedCheckboxLabel=$(escapeJSONString "${checkboxLabel}")
        escapedItemID=$(escapeJSONString "${itemID}")
        escapedIconURL=$(escapeJSONString "${itemIconURL}")
        checkboxItemsJSON="${checkboxItemsJSON}${separator}{\"label\":\"${escapedCheckboxLabel}\",\"name\":\"${escapedItemID}\",\"checked\":${checkboxChecked},\"disabled\":${checkboxDisabled},\"icon\":\"${escapedIconURL}\"}"
        separator=","
    done

    selectionDialogCheckboxesJSON="[${checkboxItemsJSON}]"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get Available Installomator Labels
# Parses the active Installomator file for top-level case arms under `case $label in`
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getAvailableInstallomatorLabels() {
    local -a availableLabels=()
    local -A availableLabelMap=()
    local labelArmsOutput=""
    local labelArm=""
    local labelAlias=""

    if ! labelArmsOutput=$(/usr/bin/awk '
        BEGIN {
            inLabelCase = 0
            caseDepth = 0
            continuedArm = ""
        }

        /^[[:space:]]*case[[:space:]]+\$label[[:space:]]+in[[:space:]]*$/ {
            inLabelCase = 1
            caseDepth = 1
            next
        }

        inLabelCase {
            if (continuedArm != "") {
                if (caseDepth != 1) {
                    exit 2
                }

                if ($0 ~ /^[[:space:]]*[A-Za-z0-9_*][A-Za-z0-9_|-]*\|\\[[:space:]]*$/) {
                    labelFragment = $0
                    sub(/^[[:space:]]*/, "", labelFragment)
                    sub(/\\[[:space:]]*$/, "", labelFragment)
                    continuedArm = continuedArm labelFragment
                    next
                }

                if ($0 ~ /^[[:space:]]*[A-Za-z0-9_*][A-Za-z0-9_|-]*\)[[:space:]]*$/) {
                    labelFragment = $0
                    sub(/^[[:space:]]*/, "", labelFragment)
                    sub(/\)[[:space:]]*$/, "", labelFragment)
                    print continuedArm labelFragment
                    continuedArm = ""
                    next
                }

                exit 2
            }

            if ($0 ~ /^[[:space:]]*case[[:space:]].*[[:space:]]+in[[:space:]]*$/) {
                caseDepth++
                next
            }

            if ($0 ~ /^[[:space:]]*esac([[:space:]]*;.*)?[[:space:]]*$/) {
                caseDepth--
                if (caseDepth == 0) {
                    exit
                }
                next
            }

            if (caseDepth == 1 && $0 ~ /^[[:space:]]*[A-Za-z0-9_*][A-Za-z0-9_|-]*\|\\[[:space:]]*$/) {
                continuedArm = $0
                sub(/^[[:space:]]*/, "", continuedArm)
                sub(/\\[[:space:]]*$/, "", continuedArm)
                next
            }

            if (caseDepth == 1 && $0 ~ /^[[:space:]]*[A-Za-z0-9_*][A-Za-z0-9_|-]*\)[[:space:]]*$/) {
                labelArm = $0
                sub(/^[[:space:]]*/, "", labelArm)
                sub(/\)[[:space:]]*$/, "", labelArm)
                print labelArm
            }
        }

        END {
            if (continuedArm != "") {
                exit 2
            }
        }
    ' "${organizationInstallomatorFile}"); then
        return 1
    fi

    while IFS= read -r labelArm; do
        [[ -z "${labelArm}" ]] && continue

        for labelAlias in "${(@s:|:)labelArm}"; do
            labelAlias="${labelAlias// /}"

            case "${labelAlias}" in
                longversion|valuesfromarguments|'*')
                    continue
                    ;;
            esac

            if (( ! ${+availableLabelMap[$labelAlias]} )); then
                availableLabelMap[$labelAlias]=1
                availableLabels+=("${labelAlias}")
            fi
        done
    done <<< "${labelArmsOutput}"

    print -l -- "${availableLabels[@]}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate Installomator Ownership (executed as root, so require an absolute, non-symlinked path that is
# root-owned with no group / other write bit at every level up to `/`)
# Sets: installomatorCheckPath, installomatorOwner, installomatorMode (describe the first failing level)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function validateInstallomatorOwnership() {
    installomatorCheckPath="${organizationInstallomatorFile}"
    installomatorOwner=""
    installomatorMode=""

    if [[ "${installomatorCheckPath}" != /* ]]; then
        installomatorOwner="relative path"
        return 1
    fi

    if [[ -L "${installomatorCheckPath}" ]]; then
        installomatorOwner="symlink"
        return 1
    fi

    while true; do
        installomatorOwner=$( /usr/bin/stat -f '%Su' "${installomatorCheckPath}" 2>/dev/null )
        installomatorMode=$( /usr/bin/stat -f '%Lp' "${installomatorCheckPath}" 2>/dev/null )

        if [[ "${installomatorOwner}" != "root" || -z "${installomatorMode}" ]] || (( 8#${installomatorMode} & 8#022 )); then
            return 1
        fi

        [[ "${installomatorCheckPath}" == "/" ]] && break
        installomatorCheckPath="${installomatorCheckPath:h}"
    done

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Normalize Installomator Label Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function normalizeInstallomatorLabels() {
    local configuredLabelCount="${#configuredInstallomatorLabels[@]}"
    local -a normalizedInstallomatorLabels=()
    local -a availableInstallomatorLabels=()
    local -A availableInstallomatorLabelMap=()
    local availableLabelsOutput=""
    local item=""
    local label=""
    local displayName=""
    local filteredLabelCount=0
    local availableLabel=""

    if [[ ${configuredLabelCount} -eq 0 ]]; then
        installomatorLabels=()
        preFlight "Aucun label Installomator configuré"
        return 0
    fi

    if [[ ! -e "${organizationInstallomatorFile}" ]]; then
        installomatorLabels=()
        warning "Installomator introuvable dans ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    elif [[ ! -f "${organizationInstallomatorFile}" ]]; then
        installomatorLabels=()
        warning "Installomator n'est pas un fichier ordinaire situé dans ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    elif [[ ! -r "${organizationInstallomatorFile}" ]]; then
        installomatorLabels=()
        warning "Installomator n'est pas lisible dans ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    elif [[ ! -x "${organizationInstallomatorFile}" ]]; then
        installomatorLabels=()
        warning "Installomator n'est pas exécutable dans ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    elif [[ ! -s "${organizationInstallomatorFile}" ]]; then
        installomatorLabels=()
        warning "Installomator dans ${organizationInstallomatorFile} fait zero octets ; Masquage des labels Installomator pour cette exécution"
        return 0
    fi

    local installomatorCheckPath=""
    local installomatorOwner=""
    local installomatorMode=""
    if ! validateInstallomatorOwnership; then
        installomatorLabels=()
        warning "Chemin d'accès à Installomator ${installomatorCheckPath} n'appartient pas à l'utilisateur root, est inscriptible par groupe / autre, ou est un lien symbolique (${installomatorOwner}:${installomatorMode}) ; Masquage des labels Installomator pour cette exécution"
        return 0
    fi

    preFlight "Installomator est disponible dans ${organizationInstallomatorFile} ; Validation des labels configurés"

    if ! availableLabelsOutput="$(getAvailableInstallomatorLabels)"; then
        installomatorLabels=()
        warning "Échec de l'analyse des labels Installomator provenant de ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    fi

    availableInstallomatorLabels=("${(@f)availableLabelsOutput}")

    if [[ ${#availableInstallomatorLabels[@]} -eq 0 ]]; then
        installomatorLabels=()
        warning "Aucun label Installomator n'a été analysé à partir de ${organizationInstallomatorFile} ; Masquage des labels Installomator pour cette exécution"
        return 0
    fi

    for availableLabel in "${availableInstallomatorLabels[@]}"; do
        availableInstallomatorLabelMap[$availableLabel]=1
    done

    for item in "${configuredInstallomatorLabels[@]}"; do
        parseInstallomatorItem "${item}"
        label="${itemLabel}"
        displayName="${itemDisplayName}"

        if (( ${+availableInstallomatorLabelMap[$label]} )); then
            normalizedInstallomatorLabels+=("${item}")
        else
            errorOut "Labels Installomator configuré '${label}' (${displayName}) n'est pas disponible dans ${organizationInstallomatorFile} ; Masquage de l'élément pour cette execution"
            ((filteredLabelCount++))
        fi
    done

    installomatorLabels=("${normalizedInstallomatorLabels[@]}")
    preFlight "Validation de labels Installomator terminée : ${#installomatorLabels[@]} disponibleq, ${filteredLabelCount} filtrés"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Normalize Jamf Policy Item Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function normalizeJamfPolicyItems() {
    local jamfPolicyItemsSetting="${enableJamfPolicyItems:l}"

    if [[ "${jamfPolicyItemsSetting}" != "true" && "${jamfPolicyItemsSetting}" != "false" ]]; then
        warning "Valeur enableJamfPolicyItems invalide '${enableJamfPolicyItems}'; passage de la valeur à true"
        enableJamfPolicyItems="true"
        jamfPolicyItemsSetting="true"
    fi

    if [[ "${jamfPolicyItemsSetting}" == "true" ]]; then
        jamfPolicyItems=("${configuredJamfPolicyItems[@]}")
    else
        jamfPolicyItems=()
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Refresh Homebrew Execution User
# Returns: 0 if a resolvable logged-in user is available (and matches the user pinned for this run), 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function refreshHomebrewExecutionUser() {
    currentLoggedInUser "false"

    # Never run Homebrew as a different user than the one resolved during pre-flight
    if [[ -n "${homebrewExecutionUser}" && "${loggedInUser}" != "${homebrewExecutionUser}" ]]; then
        errorOut "L'utilisateur de la console est passé de ${homebrewExecutionUser} à ${loggedInUser} ; Homebrew ne sera pas exécuté sous un autre utilisateur"
        loggedInUser="${homebrewExecutionUser}"
        return 1
    fi

    if isSystemConsoleUser "${loggedInUser}"; then
        return 1
    fi

    if ! /usr/bin/id -u "${loggedInUser}" >/dev/null 2>&1; then
        return 1
    fi

    updateLoggedInUserDetails

    # Non-admin users can't write to /Applications, so Homebrew would prompt for sudo
    if /usr/sbin/dseditgroup -o checkmember -m "${loggedInUser}" admin >/dev/null 2>&1; then
        loggedInUserIsAdmin="true"
    else
        loggedInUserIsAdmin="false"
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Detect Effective Homebrew Binary
# Returns: Path to Homebrew binary on stdout, or empty if unavailable
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function detectHomebrewBinary() {
    if [[ -n "${brewPath}" ]]; then
        if [[ -x "${brewPath}" ]]; then
            print -r -- "${brewPath}"
        fi
        return 0
    fi

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        print -r -- "/opt/homebrew/bin/brew"
        return 0
    fi

    if [[ -x "/usr/local/bin/brew" ]]; then
        print -r -- "/usr/local/bin/brew"
        return 0
    fi

    print -r -- ""
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Resolve git for Homebrew
# Sets homebrewGitPath (empty when no usable git is found)
# Returns: 0 if git is found, 1 otherwise
# Uses `-x` tests only; never runs /usr/bin/git, whose CLT stub would prompt the logged-in user
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function resolveHomebrewGitPath() {
    local developerDirectory=""
    local candidatePath=""
    local -a candidatePaths=()

    homebrewGitPath=""

    developerDirectory="$( /usr/bin/xcode-select -print-path 2>/dev/null )"
    if [[ -n "${developerDirectory}" && "${developerDirectory}" != "/" ]]; then
        candidatePaths+=("${developerDirectory}/usr/bin/git")
    fi

    candidatePaths+=(
        "/Library/Developer/CommandLineTools/usr/bin/git"
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
    )

    # A brewed git also satisfies Homebrew (`${effectiveBrewPath:h:h}` of an empty path is ".", so skip it)
    if [[ -n "${effectiveBrewPath}" ]]; then
        candidatePaths+=("${effectiveBrewPath:h:h}/bin/git")
    fi

    for candidatePath in "${candidatePaths[@]}"; do
        if [[ -f "${candidatePath}" && -x "${candidatePath}" ]]; then
            homebrewGitPath="${candidatePath}"
            return 0
        fi
    done

    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check Whether Command Line Tools Bootstrap Is Expected
# Returns: 0 when the setting is enabled, Homebrew work is selected (Homebrew items or the
# Installomator `homebrew` label), and git is missing; 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isCommandLineToolsBootstrapExpected() {
    if [[ "${homebrewAutoInstallCommandLineTools:l}" != "true" || "${enableHomebrewItems:l}" != "true" ]]; then
        return 1
    fi

    if [[ ${#selectedHomebrewItems[@]} -eq 0 && ${selectedInstallomatorLabels[(Ie)homebrew]} -eq 0 ]]; then
        return 1
    fi

    if resolveHomebrewGitPath; then
        return 1
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Build Command Line Tools Inspect Mode Item
# Input: guiIndex
# Output: Inspect Mode item JSON; completes when commandLineToolsInspectMarkerFile appears
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function buildCommandLineToolsInspectItemJSON() {
    local guiIndex="$1"

    print -r -- "{
            \"id\": \"commandLineTools\",
            \"displayName\": \"Command Line Tools (for Homebrew)\",
            \"guiIndex\": ${guiIndex},
            \"paths\": [\"$(escapeJSONString "${commandLineToolsInspectMarkerFile}")\"],
            \"icon\": \"SF=terminal\"
        }"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Mark Command Line Tools Inspect Mode Item Complete
# Writes the marker (root-owned runtime directory) only once git is available, so a failed install
# leaves the row waiting like any other failed item; git from Xcode or brew also completes it
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function markCommandLineToolsInspectItemComplete() {
    if [[ -z "${commandLineToolsInspectMarkerFile}" || -e "${commandLineToolsInspectMarkerFile}" ]]; then
        return 0
    fi

    if resolveHomebrewGitPath; then
        : > "${commandLineToolsInspectMarkerFile}" 2>/dev/null
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Normalize Homebrew Item Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function normalizeHomebrewItems() {
    local homebrewItemsSetting="${enableHomebrewItems:l}"
    local commandLineToolsSetting="${homebrewAutoInstallCommandLineTools:l}"
    local detectedBrewPath=""
    local filteredItemCount=0
    local item=""
    local -a normalizedHomebrewItems=()

    if [[ "${homebrewItemsSetting}" != "true" && "${homebrewItemsSetting}" != "false" ]]; then
        warning "Valeur enableHomebrewItems invalide '${enableHomebrewItems}' ; Retour à la valeur par défaut true"
        enableHomebrewItems="true"
        homebrewItemsSetting="true"
    fi

    if [[ "${commandLineToolsSetting}" != "true" && "${commandLineToolsSetting}" != "false" ]]; then
        warning "Valeur homebrewAutoInstallCommandLineTools invalide '${homebrewAutoInstallCommandLineTools}' ; Retour à la valeur par défaut true"
        homebrewAutoInstallCommandLineTools="true"
    fi

    if [[ "${homebrewItemsSetting}" != "true" ]]; then
        homebrewItems=()
        effectiveBrewPath=""
        return 0
    fi

    homebrewItems=("${configuredHomebrewItems[@]}")

    if [[ ${#homebrewItems[@]} -eq 0 ]]; then
        preFlight "No Homebrew items configured"
        effectiveBrewPath=""
        return 0
    fi

    detectedBrewPath="$(detectHomebrewBinary)"
    if [[ -z "${detectedBrewPath}" ]]; then
        if [[ -n "${brewPath}" ]]; then
            warning "Le chemin d'accès configuré pour Homebrew n'est pas disponible ou n'est pas exécutable : ${brewPath}"
        else
            warning "Fichier binaire Homebrew introuvable à l'emplacement /opt/homebrew/bin/brew ou /usr/local/bin/brew"
        fi
        warning "Les éléments Homebrew seront masqués dans cette session tant que Homebrew ne sera pas installé"
        homebrewItems=()
        effectiveBrewPath=""
        return 0
    fi

    effectiveBrewPath="${detectedBrewPath}"
    preFlight "Fichier binaire Homebrew trouvé ici : ${effectiveBrewPath}"

    if [[ "${effectiveBrewPath:h:h}" != "${homebrewPrefix}" ]]; then
        warning "Fichier binaire Homebrew ${effectiveBrewPath} ne correspond pas au préfixe de validation ${homebrewPrefix} ; Les vérifications d'omission et d'achèvement pour les éléments Homebrew peuvent être erronées"
    fi

    # Log only; Command Line Tools install waits until first Homebrew use so the selection dialog isn't delayed
    if resolveHomebrewGitPath; then
        preFlight "git disponible pour Homebrew dans ${homebrewGitPath}"
    elif [[ "${homebrewAutoInstallCommandLineTools:l}" == "true" ]]; then
        warning "git non trouvé ; Installera les outils de ligne de commande avant la première utilisation de Homebrew"
    else
        warning "git non trouvé ; La mise à jour de Brew et les sources tierces ne sont pas disponibles (homebrewAutoInstallCommandLineTools=false)"
    fi

    if ! refreshHomebrewExecutionUser; then
        warning "Aucun utilisateur connecté n'est disponible pour exécuter Homebrew ; Masquage des éléments Homebrew pour cette éxécution"
        homebrewItems=()
        effectiveBrewPath=""
        return 0
    fi

    homebrewExecutionUser="${loggedInUser}"

    if [[ "${loggedInUserIsAdmin}" == "false" ]]; then
        preFlight "Les éléments Homebrew seont éxécutés en tant que ${loggedInUser} (non-admin ; Installation casks dans ~/Applications; les étapes nécessitant l'utilisation de sudo échouent rapidement)"
    else
        preFlight "Les éléments Homebrew s'exécuteront en tant que ${loggedInUser}"
    fi

    for item in "${configuredHomebrewItems[@]}"; do
        parseHomebrewItem "${item}"

        if [[ "${itemBrewMode}" != "cask" && "${itemBrewMode}" != "formula" ]]; then
            errorOut "Élément Homebrew configuré '${itemHomebrewID}' (${itemDisplayName}) avec un prefixe invalide ; utilisez 'cask:' ou 'formula:'"
            ((filteredItemCount++))
            continue
        fi

        if [[ -z "${itemBrewToken}" || "${itemBrewToken}" == "${itemHomebrewID}" ]]; then
            errorOut "L'élément Homebrew configuré '${itemHomebrewID}' (${itemDisplayName}) n'a pas de jeton de package ; Masquage de l'élément pour cette éxécution"
            ((filteredItemCount++))
            continue
        fi

        normalizedHomebrewItems+=("${item}")
    done

    homebrewItems=("${normalizedHomebrewItems[@]}")
    preFlight "Validation des éléments Homebrew terminée : ${#homebrewItems[@]} disponibles, ${filteredItemCount} filtrés"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check Configured Homebrew Item
# Input: Item ID
# Output: 0 if item exists in configuredHomebrewItems, 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isConfiguredHomebrewItem() {
    local itemID="$1"
    local item

    for item in "${configuredHomebrewItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            return 0
        fi
    done

    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check Configured Jamf Policy Item
# Input: Item ID
# Output: 0 if item exists in configuredJamfPolicyItems, 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isConfiguredJamfPolicyItem() {
    local itemID="$1"
    local item

    for item in "${configuredJamfPolicyItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            return 0
        fi
    done

    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check Configured Installomator Label
# Input: Item ID
# Output: 0 if item exists in configuredInstallomatorLabels, 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isConfiguredInstallomatorLabel() {
    local itemID="$1"
    local item

    for item in "${configuredInstallomatorLabels[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            return 0
        fi
    done

    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get All Item IDs
# Returns: Array of all item identifiers (labels + triggers)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getAllItemIDs() {
    local allIDs=()
    
    # Add Installomator labels
    for item in "${installomatorLabels[@]}"; do
        local parts=("${(@s: | :)item}")
        allIDs+=("${parts[1]}")
    done
    
    # Add Jamf policy triggers
    for item in "${jamfPolicyItems[@]}"; do
        local parts=("${(@s: | :)item}")
        allIDs+=("${parts[1]}")
    done

    # Add Homebrew item IDs
    for item in "${homebrewItems[@]}"; do
        local parts=("${(@s: | :)item}")
        allIDs+=("${parts[1]}")
    done
    
    print -r -- "${allIDs[@]}"
}

function getAllItemIDsCSV() {
    local allIDs=()

    allIDs=($(getAllItemIDs))
    print -r -- "${(j:,:)allIDs}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Warn on Duplicate Item IDs
# getItemType() returns the first match (Installomator, then Jamf, then Homebrew), so an ID configured
# in more than one array always resolves to the earlier type
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function warnDuplicateItemIDs() {
    local -A seenItemIDs=()
    local item=""
    local itemID=""
    local itemSource=""
    local -a parts=()

    for itemSource in configuredInstallomatorLabels configuredJamfPolicyItems configuredHomebrewItems; do
        for item in "${(@P)itemSource}"; do
            parts=("${(@s: | :)item}")
            itemID="${parts[1]}"
            [[ -z "${itemID}" ]] && continue

            if [[ -n "${seenItemIDs[${itemID}]}" ]]; then
                warning "L'ID de l'élément '${itemID}' est configurés à la fois dans ${seenItemIDs[${itemID}]} et ${itemSource} ; seul l'entrée ${seenItemIDs[${itemID}]} sera utilisée"
            else
                seenItemIDs[${itemID}]="${itemSource}"
            fi
        done
    done
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get Item Type
# Input: Item ID
# Output: "installomator" or "jamf" or empty string if not found
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getItemType() {
    local itemID="$1"
    
    # Check Installomator labels
    for item in "${installomatorLabels[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "installomator"
            return 0
        fi
    done
    
    # Check Jamf policy items
    for item in "${jamfPolicyItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "jamf"
            return 0
        fi
    done

    # Check Homebrew items
    for item in "${homebrewItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "homebrew"
            return 0
        fi
    done
    
    print -r -- ""
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get Item Configuration
# Input: Item ID
# Output: Full configuration string
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getItemConfig() {
    local itemID="$1"
    
    # Check Installomator labels
    for item in "${installomatorLabels[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "${item}"
            return 0
        fi
    done
    
    # Check Jamf policy items
    for item in "${jamfPolicyItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "${item}"
            return 0
        fi
    done

    # Check Homebrew items
    for item in "${homebrewItems[@]}"; do
        local parts=("${(@s: | :)item}")
        if [[ "${parts[1]}" == "${itemID}" ]]; then
            print -r -- "${item}"
            return 0
        fi
    done
    
    print -r -- ""
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Completion Report Helpers
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function escapeJSONString() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    print -r -- "${value}"
}

function buildJSONStringArray() {
    local value=""
    local jsonOutput=""
    local separator=""

    for value in "$@"; do
        [[ -z "${value}" ]] && continue
        jsonOutput="${jsonOutput}${separator}        \"$(escapeJSONString "${value}")\""
        separator=$',\n'
    done

    print -r -- "${jsonOutput}"
}

function getHomebrewCacheDirectory() {
    if [[ -n "${loggedInUserHomeDirectory}" ]]; then
        print -r -- "${loggedInUserHomeDirectory}/Library/Caches/Homebrew"
    else
        print -r -- ""
    fi
}

# Shared `env` prefix for every brew command run as the logged-in user
# HOMEBREW_NO_SUDO=1 makes brew fail instead of prompting for a password (e.g., non-admin or EPM-managed sudo)
function setHomebrewCommandEnvironment() {
    homebrewCommandEnvironment=(
        /usr/bin/env
        HOME="${loggedInUserHomeDirectory}"
        USER="${loggedInUser}"
        LOGNAME="${loggedInUser}"
        XDG_CACHE_HOME="${loggedInUserHomeDirectory}/Library/Caches"
        HOMEBREW_CACHE="$(getHomebrewCacheDirectory)"
        NONINTERACTIVE=1
        HOMEBREW_NO_SUDO=1
        HOMEBREW_NO_ENV_HINTS=1
    )
}

function isValidationPathPresent() {
    local validationPath="$1"

    [[ -n "${validationPath}" && -e "${validationPath}" ]]
}

function addCompletionReportRecord() {
    local displayName="$1"
    local statusKey="$2"
    local dialogStatus="$3"
    local iconURL="$4"
    local subtitle="$5"
    local statusText="$6"

    [[ -z "${iconURL}" ]] && iconURL="${mainDialogIcon}"

    completionReportRecords+=("${displayName}"$'\t'"${statusKey}"$'\t'"${dialogStatus}"$'\t'"${iconURL}"$'\t'"${subtitle}"$'\t'"${statusText}")
}

function buildCompletionReportListItemsJSON() {
    if [[ ${#completionReportRecords[@]} -eq 0 ]]; then
        print -r -- "[]"
        return 0
    fi

    local -a sortedRecords
    sortedRecords=("${(@f)$(printf '%s\n' "${completionReportRecords[@]}" | LC_ALL=C sort -f)}")

    local record=""
    local displayName=""
    local statusKey=""
    local dialogStatus=""
    local iconURL=""
    local subtitle=""
    local statusText=""
    local escapedDisplayName=""
    local escapedIconURL=""
    local escapedSubtitle=""
    local escapedStatusText=""
    local listItemsJSON=""
    local separator=""

    for record in "${sortedRecords[@]}"; do
        IFS=$'\t' read -r displayName statusKey dialogStatus iconURL subtitle statusText <<< "${record}"

        escapedDisplayName=$(escapeJSONString "${displayName}")
        escapedIconURL=$(escapeJSONString "${iconURL}")
        escapedSubtitle=$(escapeJSONString "${subtitle}")
        escapedStatusText=$(escapeJSONString "${statusText}")

        listItemsJSON="${listItemsJSON}${separator}
        {\"title\":\"${escapedDisplayName}\",\"subtitle\":\"${escapedSubtitle}\",\"icon\":\"${escapedIconURL}\",\"status\":\"${dialogStatus}\",\"statustext\":\"${escapedStatusText}\",\"iconalpha\":1}"
        separator=","
    done

    print -r -- "[
${listItemsJSON}
    ]"
}



####################################################################################################
#
# swiftDialog Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogInstall() {
    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" \
        | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Validate URL was retrieved
    if [[ -z "${dialogURL}" ]]; then
        fatal "Impossible de récupérer l'URL de téléchargement de swiftDialog via l'API GitHub"
    fi

    # Validate URL format
    if [[ ! "${dialogURL}" =~ ^https://github\.com/ ]]; then
        fatal "Format d'URL swiftDialog non valide : ${dialogURL}"
    fi

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installation de swiftDialog depuis ${dialogURL}..."

    # Create temporary working directory
    dialogTemporaryDirectory=$( mktemp -d "/private/tmp/${organizationScriptName}.XXXXXX" )
    if [[ -z "${dialogTemporaryDirectory}" || ! -d "${dialogTemporaryDirectory}" ]]; then
        fatal "Impossible de créer le répertoire de travail temporaire pour l'installation de swiftDialog"
    fi

    # Download the installer package with timeouts
    if ! curl --location --silent --fail --connect-timeout 10 --max-time 60 \
             "$dialogURL" -o "${dialogTemporaryDirectory}/Dialog.pkg"; then
        rm -Rf "${dialogTemporaryDirectory}"
        dialogTemporaryDirectory=""
        fatal "Échec du téléchargement du package swiftDialog"
    fi

    # Verify the download (require Gatekeeper acceptance and notarization before trusting the Team ID)
    local spctlOutput
    spctlOutput=$( spctl -a -vv -t install "${dialogTemporaryDirectory}/Dialog.pkg" 2>&1 )
    teamID=""
    if [[ "${spctlOutput}" == *": accepted"* && "${spctlOutput}" == *"source=Notarized Developer ID"* ]]; then
        teamID=$( print -r -- "${spctlOutput}" | awk '/origin=/ {print $NF }' | tr -d '()' )
    else
        warning "Le package swiftDialog n'a pas été accepté par Gatekeeper en tant que package associé à un identifiant de développeur certifié."
    fi

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

        if ! installer -pkg "${dialogTemporaryDirectory}/Dialog.pkg" -target /; then
            rm -Rf "${dialogTemporaryDirectory}"
            dialogTemporaryDirectory=""
            fatal "Échec d'installation du package swiftDialog"
        fi
        sleep 2
        dialogVersion=$( "${dialogBinary}" --version 2>/dev/null )
        preFlight "Version ${dialogVersion} de swiftDialog installée ; passage à l'étape suivante..."

    else

        # Display a so-called "simple" dialog if Team ID fails to validate (as the logged-in user, when available)
        currentLoggedInUser "false"
        if isSystemConsoleUser "${loggedInUser}"; then
            loggedInUser=""
        fi
        runAsUser "${loggedInUser}" /usr/bin/osascript -e 'display dialog "Veuillez contacter le support technique O2i et leur donner le code erreur suivant :\r\r• Vérification identifiant équipe Dialog échoué\r\r" with title "'"${humanReadableScriptName}"' Error" buttons {"Close"} with icon caution'
        exit "1"

    fi

    # Remove the temporary working directory when done
    rm -Rf "${dialogTemporaryDirectory}"
    dialogTemporaryDirectory=""

}

function dialogCheck() {

    # Check for Dialog and install if not found
    if [[ ! -d "${dialogAppBundle}" ]]; then

        preFlight "swiftDialog not found; installing …"
        dialogInstall
        dialogVersion=$( [[ -x "${dialogBinary}" ]] && "${dialogBinary}" --version 2>/dev/null )
        if [[ -z "${dialogVersion}" ]] || ! is-at-least "${swiftDialogMinimumRequiredVersion}" "${dialogVersion}"; then
            fatal "swiftDialog n'est toujours pas trouvé ; Les téléchargements depuis GitHub sont-ils bloqués sur ce Mac ?"
        fi

    else

        dialogVersion=$( [[ -x "${dialogBinary}" ]] && "${dialogBinary}" --version 2>/dev/null )
        if [[ -z "${dialogVersion}" ]] || ! is-at-least "${swiftDialogMinimumRequiredVersion}" "${dialogVersion}"; then

            preFlight "Version swiftDialog '${dialogVersion}' trouvé mais swiftDialog ${swiftDialogMinimumRequiredVersion} ou plus récent est necessaire; Mise à jour en cours..."
            dialogInstall
            dialogVersion=$( [[ -x "${dialogBinary}" ]] && "${dialogBinary}" --version 2>/dev/null )
            if [[ -z "${dialogVersion}" ]] || ! is-at-least "${swiftDialogMinimumRequiredVersion}" "${dialogVersion}"; then
                fatal "Impossible de mettre à jour swiftDialog ; Les téléchargements depuis GitHub sont-ils bloqués sur ce Mac ?"
            fi

        else

            preFlight "swiftDialog version ${dialogVersion} trouvé ; En cours de traitement..."

        fi

    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Formatted Elapsed Time
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function formattedElapsedTime() {
    /usr/bin/printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60))
}

# Root-owned (755) per-run directory: the logged-in user can own and read hand-off files inside it,
# but can't delete or replace them with symlinks (as they could in sticky /var/tmp)
function createDialogRuntimeDirectory() {
    if [[ -n "${dialogRuntimeDirectory}" && -d "${dialogRuntimeDirectory}" ]]; then
        return 0
    fi

    dialogRuntimeDirectory=$( /usr/bin/mktemp -d "/var/tmp/${organizationScriptName}.XXXXXX" )
    if [[ -z "${dialogRuntimeDirectory}" || ! -d "${dialogRuntimeDirectory}" ]]; then
        fatal "Échec de la création du répertoire d'exécution de Dialog"
    fi

    if ! /bin/chmod 755 "${dialogRuntimeDirectory}" 2>/dev/null; then
        fatal "Échec de la configuration des droits d'accès sur le répertoire d'exécution de Dialog"
    fi

    info "Répertoire d'exécution de Dialog créé à l'emplacement suivant : ${dialogRuntimeDirectory}"
}

function createDialogCommandFile() {
    createDialogRuntimeDirectory

    dialogCommandFile="${dialogRuntimeDirectory}/commandFile"
    if ! : > "${dialogCommandFile}" 2>/dev/null; then
        fatal "Échec de la création du fichier de commande de Dialog"
    fi

    if [[ -n "${loggedInUser}" ]]; then
        if ! /bin/chmod 600 "${dialogCommandFile}" 2>/dev/null; then
            fatal "Impossible de définir les autorisations sur le fichier de commande de Dialog pour ${loggedInUser}."
        fi

        if ! /usr/sbin/chown "${loggedInUser}" "${dialogCommandFile}" 2>/dev/null; then
            fatal "Échec de la définition des droits de propriété sur le fichier de commande de Dialog pour ${loggedInUser}."
        fi
    fi

    info "Fichiers de commande de Dialog créé à l'emplacement suivant : ${dialogCommandFile}"
}

function removeDialogCommandFile() {
    if [[ -n "${dialogCommandFile}" && -e "${dialogCommandFile}" ]]; then
        rm -f -- "${dialogCommandFile}" 2>/dev/null
    fi

    dialogCommandFile=""
}

function closeInspectMode() {
    local reason="${1:-cleanup}"
    local gracefulWait="${2:-5}"
    local waitCount=0

    if [[ -n "${dialogCommandFile}" && -e "${dialogCommandFile}" ]]; then
        info "Demande de fermeture du Inspect Mode via le fichier de commande (${reason})"
        runAsUser "${loggedInUser}" /bin/sh -c '/bin/echo "quit:" >> "$1"' _ "${dialogCommandFile}" 2>/dev/null || warning "Échec de l'écriture de la commande quit dans le fichier de commandes de Dialog"
    fi

    if [[ -n "${dialogPID}" ]]; then
        while kill -0 "${dialogPID}" 2>/dev/null && (( waitCount < gracefulWait )); do
            /bin/sleep 1
            ((waitCount++))
        done

        if kill -0 "${dialogPID}" 2>/dev/null; then
            warning "Enveloppe PID du Inspect Mode ${dialogPID} ne s'est pas fermé après ${gracefulWait} secondes ; Fermeture"
            kill "${dialogPID}" 2>/dev/null || true
            /bin/sleep 1
        fi
    fi

    dialogPID=""
    removeDialogCommandFile
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {
    exitCode="${1:-0}"
    
    notice "Exiting …"
    
    if [[ -n "${dialogPID}" || ( -n "${dialogCommandFile}" && -e "${dialogCommandFile}" ) ]]; then
        closeInspectMode "script exit"
    fi
    
    cleanup
    
    info "Temps total écoulé : $(formattedElapsedTime)"
    info "Si long !"
    
    exit "${exitCode}"
}



####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
    /usr/bin/touch "${scriptLog}"
    if [[ -f "${scriptLog}" ]]; then
        /bin/chmod 640 "${scriptLog}"
        preFlight "Création du fichier scriptLog spécifié : ${scriptLog}"
    else
        fatal "Impossible de créer le fichier scriptLog spécifié '${scriptLog}'; Fermeture.\n\n(Ce script s'exécute-t-il en tant que 'root' ?)"
    fi
fi

# Check and rotate log if exceeds max size
logSize=$(/usr/bin/stat -f%z "${scriptLog}" 2>/dev/null || /bin/echo "0")
maxLogSize=$((10 * 1024 * 1024))  # 10MB

if (( logSize > maxLogSize )); then
    preFlight "Le fichier de Log excède ${maxLogSize} octets ; Rotation du ficher"
    if /bin/mv "${scriptLog}" "${scriptLog}.$(/bin/date +%s).old" 2>/dev/null; then
        /usr/bin/touch "${scriptLog}" && /bin/chmod 640 "${scriptLog}"
        preFlight "Fichier journal renouvelé"

        # Keep only the three newest rotated logs
        rotatedLogs=( "${scriptLog}".*.old(N.Om) )
        if (( ${#rotatedLogs} > 3 )); then
            /bin/rm -f -- "${(@)rotatedLogs[1,-4]}"
            preFlight "Suppression de $(( ${#rotatedLogs} - 3 )) fichiers de log(s) plus anciens"
        fi
    else
        warning "Impossible de renouveler le fichier journal"
    fi
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# https://snelson.us/sym\n###\n"
preFlight "Lancement..."



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    fatal "Ce script doit être lencé en tant que root ; Fermeture..."
fi

preFlight "Exécution en tant que root ; Poursuite de l'opération..."

case "${operationMode}" in
    interactive|silent ) ;;
    * ) fatal "operationMode invalide '${operationMode}' ; attendu 'interactive' ou 'silent'" ;;
esac

dialogHeight="${dialogHeight//[[:space:]]/}"
if [[ "${dialogHeight}" =~ ^[0-9]+$ ]] && (( 10#${dialogHeight} > 0 )); then
    dialogHeight="$(( 10#${dialogHeight} ))"
else
    warning "dialogHeight invalide '${dialogHeight}'; utilisation des paramètres par défaut 675"
    dialogHeight="675"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate swiftDialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

dialogCheck



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Normalize Jamf Policy Item Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

normalizeJamfPolicyItems

if [[ "${enableJamfPolicyItems:l}" == "true" ]]; then
    preFlight "Règles Jamf activées (${#jamfPolicyItems[@]} configuré)"
else
    preFlight "Éléments de stratégie Jamf désactivés par la configuration"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts (Interactive Mode)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${operationMode}" != "silent" ]]; then
    maxWait=120
    counter=0

    preFlight "Vérifier les comptes système connectés..."
    currentLoggedInUser

    until ! isSystemConsoleUser "${loggedInUser}"; do
        if [[ "${counter}" -ge "${maxWait}" ]]; then
            fatal "Aucun utilisateur valide n'est connecté après ${maxWait} secondes ; Fermeture."
        fi
        sleep 1
        ((counter++))
        currentLoggedInUser
        preFlight "Compteur d'utilisateurs connectés : ${counter}"
    done

    if ! /usr/bin/id -u "${loggedInUser}" >/dev/null 2>&1; then
        fatal "UTilisateur connecté '${loggedInUser}' ne peut pas être résolu; Fermeture."
    fi

    updateLoggedInUserDetails
    preFlight "Prénom de l'utilisateur actuellement connecté (ID): ${loggedInUserFirstname} (${loggedInUserID})"
    preFlight "Utilisateur connecté et validé '${loggedInUser}'."
else
    preFlight "Mode silent activé ; Ignorer la vérification préalable de l'utilisateur connecté."
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Normalize Homebrew Item Availability
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

normalizeHomebrewItems

if [[ "${enableHomebrewItems:l}" == "true" ]]; then
    preFlight "Éléments Homebrew activés (${#homebrewItems[@]} configuré pour cette éxécution)"
else
    preFlight "Éléments Homebrew désactivé par la configuration"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Installomator Labels
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

normalizeInstallomatorLabels



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Jamf Binary (if Jamf policy items configured)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ${#jamfPolicyItems[@]} -gt 0 ]]; then
    if [[ ! -x "${jamfBinary}" ]]; then
        warning "binaire Jamf introuvable dans ${jamfBinary}"
        warning "Les règles Jamf seront ignorées"
        jamfPolicyItems=()
    else
        preFlight "binaire Jamf trouvé dans ${jamfBinary}"
    fi
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Duplicate Item IDs
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

warnDuplicateItemIDs



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Vérifications avant éxécution terminées !"



####################################################################################################
#
# Inspect Mode Configuration Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Create swiftDialog Inspect Mode Configuration
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function createSYMLiteInspectConfig() {
    local totalItems=${#selectedItems[@]}
    local dialogTitle=""
    local messageText
    local cachePathsJSON
    local sideMessageJSON
    local logMonitorJSON=""
    local -a cachePaths=()
    local -a sideMessages=()
    local hasInstallomator="false"
    local hasJamf="false"
    local hasHomebrew="false"

    createDialogRuntimeDirectory

    dialogInspectModeJSONFile="${dialogRuntimeDirectory}/inspectConfig.json"
    if ! : > "${dialogInspectModeJSONFile}" 2>/dev/null; then
        fatal "Échec de la création du fichier de configuration d'inspection de Dialog"
    fi
    
    # Build items array JSON with guiIndex
    local itemsJSON=""
    local -a itemJSONBlocks=()
    local guiIndex=0
    local commandLineToolsRowPending="false"

    # Command Line Tools row sits where the bootstrap runs: before the `homebrew` label or the first Homebrew item
    commandLineToolsInspectMarkerFile=""
    if isCommandLineToolsBootstrapExpected; then
        commandLineToolsInspectMarkerFile="${dialogRuntimeDirectory}/commandLineToolsComplete"
        commandLineToolsRowPending="true"
        ((totalItems++))
    fi

    for itemID in "${selectedItems[@]}"; do
        local itemType
        itemType=$(getItemType "${itemID}")

        local itemConfig
        itemConfig=$(getItemConfig "${itemID}")

        if [[ "${commandLineToolsRowPending}" == "true" && "${itemType}" == "homebrew" ]]; then
            itemJSONBlocks+=("$(buildCommandLineToolsInspectItemJSON "${guiIndex}")")
            commandLineToolsRowPending="false"
            ((guiIndex++))
        fi

        if [[ "${itemType}" == "installomator" ]]; then
            parseInstallomatorItem "${itemConfig}"
            if [[ "${commandLineToolsRowPending}" == "true" && "${itemLabel}" == "homebrew" ]]; then
                itemJSONBlocks+=("$(buildCommandLineToolsInspectItemJSON "${guiIndex}")")
                commandLineToolsRowPending="false"
                ((guiIndex++))
            fi
            local jsonBlock="{
            \"id\": \"$(escapeJSONString "${itemLabel}")\",
            \"displayName\": \"$(escapeJSONString "${itemDisplayName}")\",
            \"guiIndex\": ${guiIndex},
            \"paths\": [\"$(escapeJSONString "${itemValidationPath}")\"],
            \"icon\": \"$(escapeJSONString "${itemIconURL}")\"
        }"
        elif [[ "${itemType}" == "jamf" ]]; then
            parseJamfPolicyItem "${itemConfig}"
            local jsonBlock="{
            \"id\": \"$(escapeJSONString "${itemTrigger}")\",
            \"displayName\": \"$(escapeJSONString "${itemDisplayName}")\",
            \"guiIndex\": ${guiIndex},
            \"paths\": [\"$(escapeJSONString "${itemValidationPath}")\"],
            \"icon\": \"$(escapeJSONString "${itemIconURL}")\"
        }"
        elif [[ "${itemType}" == "homebrew" ]]; then
            parseHomebrewItem "${itemConfig}"
            local jsonBlock="{
            \"id\": \"$(escapeJSONString "${itemHomebrewID}")\",
            \"displayName\": \"$(escapeJSONString "${itemDisplayName}")\",
            \"guiIndex\": ${guiIndex},
            \"paths\": [\"$(escapeJSONString "${itemValidationPath}")\"],
            \"icon\": \"$(escapeJSONString "${itemIconURL}")\"
        }"
        else
            warning "Type d'élément inconnu pour l'ID : ${itemID}"
            continue
        fi
        
        itemJSONBlocks+=("${jsonBlock}")
        ((guiIndex++))
    done

    itemsJSON="${(pj:,\n        :)itemJSONBlocks}"

    [[ ${#selectedInstallomatorLabels[@]} -gt 0 ]] && hasInstallomator="true"
    [[ ${#selectedJamfPolicies[@]} -gt 0 ]] && hasJamf="true"
    [[ ${#selectedHomebrewItems[@]} -gt 0 ]] && hasHomebrew="true"

    cachePaths+=("/Library/Managed Installs/Cache")

    # Command Line Tools install runs first and takes minutes, so lead with its side message
    # (Preset 3 shows only the first side message; swiftDialog doesn't rotate them there)
    if [[ -n "${commandLineToolsInspectMarkerFile}" ]]; then
        sideMessages+=("L'installation des outils en ligne de commande d'Apple pour Homebrew peut prendre plusieurs minutes (sans indication de progression visible).")
    fi

    sideMessages+=("Merci de votre patience.")
    sideMessages+=("La progression est suivie en surveillant l'apparition des fichiers.")
    sideMessages+=("Veuillez patienter pendant le traitement des éléments.")
    sideMessages+=("Chaque élément est considéré comme terminé dès que son chemin de validation s'affiche.")
    sideMessages+=("Ce processus peut prendre plusieurs minutes.")
    sideMessages+=("L'installation se terminera automatiquement.")
    sideMessages+=("Un redémarrage peut s'avérer nécessaire une fois l'opération terminée.")

    if [[ "${hasInstallomator}" == "true" ]]; then
        logMonitorJSON='    "logMonitor": {
        "path": "'"$(escapeJSONString "${installomatorLog}")"'",
        "preset": "installomator",
        "autoMatch": true,
        "startFromEnd": true
    },'
        cachePaths+=("/Library/Application Support/Installomator/Downloads")
        sideMessages+=("Les Apps sont en cours d'installation via Installomator.")
    fi

    if [[ "${hasJamf}" == "true" ]]; then
        cachePaths+=("/Library/Application Support/JAMF/Downloads")
        sideMessages+=("Les règles sont déployées via Jamf Pro.")
    fi

    if [[ "${hasHomebrew}" == "true" ]]; then
        [[ -n "${loggedInUserHomeDirectory}" ]] && cachePaths+=("${loggedInUserHomeDirectory}/Library/Caches/Homebrew")
        cachePaths+=("/Library/Caches/Homebrew")
        sideMessages+=("Les packages Homebrew approuvés sont installés dans le contexte de l'utilisateur connecté.")
    fi

    cachePathsJSON="$(buildJSONStringArray "${cachePaths[@]}")"
    sideMessageJSON="$(buildJSONStringArray "${sideMessages[@]}")"

    if [[ "${hasJamf}" == "true" && "${hasInstallomator}" != "true" && "${hasHomebrew}" != "true" ]]; then
        dialogTitle="Éxécution de la règle ${totalItems}"
        [[ ${totalItems} -gt 1 ]] && dialogTitle="${dialogTitle}ies"
        messageText="Exécution des règles sélectionnées. Les éléments sont considérés comme installés lorsqu'ils apparaissent dans leurs chemins de validation."
    elif [[ "${hasJamf}" == "true" ]]; then
        dialogTitle="Installation de ${totalItems} éléments"
        [[ ${totalItems} -gt 1 ]] && dialogTitle="${dialogTitle}s"
        messageText="Traitement des Apps et règles sélectionnées. Les éléments sont considérés comme installés lorsqu'ils apparaissent dans leurs chemins de validation."
    else
        dialogTitle="Installation de ${totalItems} éléments"
        [[ ${totalItems} -gt 1 ]] && dialogTitle="${dialogTitle}s"
        messageText="Installation des Apps sélectionnées. Les éléments sont considérés comme installés lorsqu'ils apparaissent dans leurs chemins de validation."
    fi

    # Short dialogs (Parameter 6 below 500) use Preset 3 (Compact) instead of the organization's preset,
    # sized to match the selection and completion dialogs (swiftDialog needs both width and height)
    local inspectPreset="${organizationPreset}"
    local inspectWindowSizeJSON=""
    local inspectButton1TextJSON='    "button1text": "Veuillez patienter...",'
    if [[ ${dialogHeight} -lt 500 ]]; then
        inspectPreset="3"
        # Preset 3 prefers config `button1text` over `autoEnableButtonText`, so omit it to let "Continue" appear on completion
        inspectButton1TextJSON=""
        inspectWindowSizeJSON="    \"width\": 900,
    \"height\": ${dialogHeight},"
        info "dialogHeight ${dialogHeight} est inférieur à 500; utilisation de Inspect Mode Preset 3 (Compact) à 900x${dialogHeight}"
    fi
    
    # Create the full JSON configuration
    # Note: Inspect Mode uses dual monitoring when Installomator items are selected:
    # - logMonitor: Parses Installomator.log for rich status updates (Installomator labels only)
    # - paths: Watches file system via FSEvents for completion detection (all item types)
    if ! /bin/cat > "${dialogInspectModeJSONFile}" <<EOF
{
    "preset": "preset${inspectPreset}",
    "title": "$(escapeJSONString "${dialogTitle}")",
    "message": "$(escapeJSONString "${messageText}")",
    "icon": "$(escapeJSONString "${mainDialogIcon}")",
    "overlayicon": "$(escapeJSONString "${organizationOverlayiconURL}")",
    "iconsize": 120,
    "size": "compact",
${inspectWindowSizeJSON}
    "options": {
        "moveable": true,
        "windowbuttons": "min"
    },
${logMonitorJSON}
    "cachePaths": [
${cachePathsJSON}
    ],
    "scanInterval": 2,
    "sideMessage": [
${sideMessageJSON}
    ],
    "sideInterval": 8,
    "highlightColor": "#51a3ef",
${inspectButton1TextJSON}
    "button1disabled": true,
    "autoEnableButton": true,
    "autoEnableButtonText": "Continue",
    "items": [
        ${itemsJSON}
    ]
}
EOF
    then
        fatal "Échec de la création du fichier d'inspection de configuration Dialog"
    else
        info "Dialog fincher d'inspection de configuration créé ici : ${dialogInspectModeJSONFile}"
    fi
    
    # Validate JSON with built-in macOS tooling.
    # `plutil -lint` only validates property lists, not raw JSON.
    local jsonValidationError
    jsonValidationError=$(/usr/bin/plutil -convert json -o /dev/null "${dialogInspectModeJSONFile}" 2>&1)
    if [[ $? -ne 0 ]]; then
        fatal "Fichier d'inspection de configuration JSON Dialog malformé : ${jsonValidationError}"
    else
        info "Fichier d'inspection de configuration JSON Dialog validé avec succès"
    fi

    return 0
}

function prepareInspectConfigForUser() {
    if [[ -z "${dialogInspectModeJSONFile}" || ! -e "${dialogInspectModeJSONFile}" ]]; then
        fatal "Le fichier d'inspection de configuration Dialog est indisponible pour le transfert d'utilisateur."
    fi

    if [[ -z "${loggedInUser}" ]]; then
        fatal "Aucun utilisateur connecté n'est disponible pour recevoir la configuration d'inspection de Dialog."
    fi

    if ! /bin/chmod 600 "${dialogInspectModeJSONFile}" 2>/dev/null; then
        fatal "Echec de mise en place des permissions sur le fichierr d'inspection de configuration Dialog pour ${loggedInUser}."
    fi

    if ! /usr/sbin/chown "${loggedInUser}" "${dialogInspectModeJSONFile}" 2>/dev/null; then
        fatal "Echec de mise en place du propriétaire sur le fichier d'inspection de configuration Dialog pour ${loggedInUser}."
    fi

    info "Le fichier d'inspection de configuration Dialog transmis à ${loggedInUser}."
}

function prepareCompletionDialogConfigForUser() {
    if [[ -z "${completionDialogJSONFile}" || ! -e "${completionDialogJSONFile}" ]]; then
        fatal "Finalisation du fichier d'inspection de configuration dialog est indisponible pour le transfert d'utilisateur."
    fi

    if [[ -z "${loggedInUser}" ]]; then
        fatal "Aucun utilisateur connecté n'est disponible pour recevoir la finalisation de la configuration de dialog."
    fi

    if ! /bin/chmod 600 "${completionDialogJSONFile}" 2>/dev/null; then
        fatal "Echec de finalisation de mise en place des permissions sur le fichier de configuration dialog pour ${loggedInUser}."
    fi

    if ! /usr/sbin/chown "${loggedInUser}" "${completionDialogJSONFile}" 2>/dev/null; then
        fatal "Echec de finalisation de mise en place du propriétaire sur le fichier de configuration dialog pour ${loggedInUser}."
    fi

    info "Finalisation de la configuration de dialog transmise à ${loggedInUser}."
}

function trimWhitespace() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    print -r -- "${value}"
}

function trimSilentModeOuterQuotes() {
    local value="$1"
    local preserveNestedQuotes="${2:-false}"
    local quotePair=""
    local leftQuote=""
    local rightQuote=""
    local innerValue=""
    local -a quotePairs=(
        "\"|\""
        "'|'"
        $'\342\200\234|\342\200\235'
        $'\342\200\230|\342\200\231'
    )

    value="$(trimWhitespace "${value}")"
    [[ -z "${value}" ]] && {
        print -r -- ""
        return 0
    }

    for quotePair in "${quotePairs[@]}"; do
        leftQuote="${quotePair%%|*}"
        rightQuote="${quotePair#*|}"

        if [[ "${value}" == "${leftQuote}"*"${rightQuote}" ]]; then
            innerValue="${value#${leftQuote}}"
            innerValue="${innerValue%${rightQuote}}"

            if [[ "${preserveNestedQuotes:l}" == "true" ]] \
            && [[ "${innerValue}" == *"${leftQuote}"* || "${innerValue}" == *"${rightQuote}"* ]]; then
                continue
            fi

            value="$(trimWhitespace "${innerValue}")"
            break
        fi
    done

    print -r -- "${value}"
}

function normalizeSilentModeItemID() {
    local itemID="$1"

    itemID="$(trimWhitespace "${itemID}")"
    [[ -z "${itemID}" ]] && {
        print -r -- ""
        return 0
    }

    itemID="$(trimSilentModeOuterQuotes "${itemID}")"
    itemID="${itemID//[[:space:]]/}"

    print -r -- "${itemID}"
}

function normalizeSilentModeCSV() {
    local csv="$1"

    csv="$(trimWhitespace "${csv}")"
    [[ -z "${csv}" ]] && {
        print -r -- ""
        return 0
    }

    csv="$(trimSilentModeOuterQuotes "${csv}" "true")"

    print -r -- "${csv}"
}

function operationsCSVIsEmpty() {
    local csv=""
    local itemID=""

    csv="$(normalizeSilentModeCSV "$1")"
    [[ -z "${csv}" ]] && return 0

    # Treat separator-only or quoted-empty input (e.g., `,` or `"",""`) as empty
    for itemID in ${(s:,:)csv}; do
        [[ -n "$(normalizeSilentModeItemID "${itemID}")" ]] && return 1
    done

    return 0
}

####################################################################################################
#
# Selection Interface Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse Operations CSV (silent mode selection; interactive mode allowlist)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseOperationsCSV() {
    local csv="$1"
    selectedItems=()
    [[ -z "${csv}" ]] && return 0

    csv="$(normalizeSilentModeCSV "${csv}")"
    [[ -z "${csv}" ]] && return 0

    local itemID
    local originalItemID
    local unknownItemMessage=""
    for itemID in ${(s:,:)csv}; do
        originalItemID="${itemID}"
        itemID="$(normalizeSilentModeItemID "${itemID}")"
        [[ -z "${itemID}" ]] && continue
        
        # Validate item exists
        local itemType
        itemType=$(getItemType "${itemID}")
        if [[ -n "${itemType}" ]]; then
            # Add only if not already present
            if [[ ! " ${selectedItems[@]} " =~ " ${itemID} " ]]; then
                selectedItems+=("${itemID}")
            fi
        else
            if isConfiguredInstallomatorLabel "${itemID}"; then
                warning "Ignore un élément du fichier CSV '${itemID}' : Le label Installomator est indisponible dans ${organizationInstallomatorFile}"
            elif [[ "${enableJamfPolicyItems:l}" != "true" ]] && isConfiguredJamfPolicyItem "${itemID}"; then
                warning "Ignore un élément du fichier CSV '${itemID}' : La règle Jamf est indisponible"
            elif [[ ! -x "${jamfBinary}" ]] && isConfiguredJamfPolicyItem "${itemID}"; then
                warning "Ignore un élément du fichier CSV '${itemID}' : Le binaire Jamf est introuvable dans ${jamfBinary}"
            elif [[ "${enableHomebrewItems:l}" != "true" ]] && isConfiguredHomebrewItem "${itemID}"; then
                warning "Ignore un élément du fichier CSV '${itemID}' : Élément Homebrew est désactivé"
            elif isConfiguredHomebrewItem "${itemID}"; then
                warning "Ignore un élément du fichier CSV '${itemID}' : Élément Homebrew indisponible dans cette éxécution"
            else
                if [[ "${itemID}" != "${originalItemID}" ]]; then
                    unknownItemMessage="ID inconnu dans le fichier CSV : '${originalItemID}' normalisé vers '${itemID}'. Les IDs doivent correspondre éxactement aux identifiers configurés ; Supprimer les guillemets superflus ou les caractères de mise en forme."
                else
                    unknownItemMessage="ID inconnu dans le fichier CSV : '${itemID}'. Les IDs doivent correspondre éxactement aux identifiers configurés ; Supprimer les guillemets superflus ou les caractères de mise en forme."
                fi
                warning "${unknownItemMessage}"
            fi
        fi
    done

    info "Fichier CSV parcouru : ${#selectedItems[@]} éléments valides séléctionnés"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse Dialog Selections (from JSON output)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseDialogSelections() {
    local output="$1"
    selectedItems=()

    if [[ ${#selectionDialogOptionRecords[@]} -gt 0 ]]; then
        local itemID=""

        for itemID in "${selectionDialogOptionRecords[@]}"; do
            if [[ -x /usr/bin/jq ]]; then
                if echo "${output}" | /usr/bin/jq -e --arg key "${itemID}" '.[$key] == true' >/dev/null 2>&1; then
                    selectedItems+=("${itemID}")
                fi
                continue
            fi

            if echo "${output}" | grep -Fq "\"${itemID}\":true" || echo "${output}" | grep -Fq "\"${itemID}\": true"; then
                selectedItems+=("${itemID}")
            fi
        done

        info "Éléments dialog analysées : ${#selectedItems[@]} éléments séléctionnés"
        return 0
    fi

    # Get all possible item IDs
    local allIDs
    allIDs=($(getAllItemIDs))

    # Primary: fixed-string search for pattern like "itemID": true
    local itemID
    for itemID in "${allIDs[@]}"; do
        if echo "${output}" | grep -Fq "\"${itemID}\":true" || echo "${output}" | grep -Fq "\"${itemID}\": true"; then
            selectedItems+=("${itemID}")
        fi
    done

    # Fallback: JSON-aware jq parsing if grep found nothing
    if [[ ${#selectedItems[@]} -eq 0 ]] && [[ -x /usr/bin/jq ]]; then
        for itemID in "${allIDs[@]}"; do
            if echo "${output}" | /usr/bin/jq -e --arg key "${itemID}" '.[$key] == true' >/dev/null 2>&1; then
                selectedItems+=("${itemID}")
            fi
        done
    fi
    
    info "Éléments dialog analysées : ${#selectedItems[@]} éléments séléctionnés"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Show No Selectable Items Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function showNoSelectableItemsDialog() {
    requireLoggedInUser "display no selectable items dialog"

    local messageText="Il n'y a actuellement aucun élément sélectionnable."

    if [[ ${selectionDialogTotalItemCount} -gt 0 ]] \
    && [[ "${selectionDialogStatusSublabelsEnabled:l}" == "true" ]] \
    && [[ ${selectionDialogDisabledItemCount} -eq ${selectionDialogTotalItemCount} ]]; then
        messageText="Tous les éléments disponibles sont déjà installés ; il n'y a donc rien de nouveau à installer pour le moment."
    fi

    "${dialogBinary}" \
        --title "${humanReadableScriptName}" \
        --infotext "${scriptVersion}" \
        --messagefont "size=${fontSize}" \
        --message "${messageText}" \
        --icon "${mainDialogIcon}" \
        --button1text "Close" \
        --height 325 \
        --width 500 2>/dev/null

    notice "Aucun élément sélectionnable n'était disponible dans le sélecteur interactif"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Show Selection Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function showSelectionDialog() {
    if [[ "${operationMode}" == "silent" ]]; then
        parseOperationsCSV "${operationsCSV}"
        if [[ ${#selectedItems[@]} -eq 0 ]]; then
            warning "IDs valides pour cette exécution : $(getAllItemIDsCSV)"
            errorOut "Silent mode: Aucune opération valide n'a été sélectionnée parmi operationsCSV"
            return 1
        fi
        return 0
    fi

    requireLoggedInUser "display selection dialog"

    selectionDialogAllowedItemIDs=()
    if ! operationsCSVIsEmpty "${operationsCSV}"; then
        parseOperationsCSV "${operationsCSV}"
        selectionDialogAllowedItemIDs=("${selectedItems[@]}")
        selectedItems=()

        if [[ ${#selectionDialogAllowedItemIDs[@]} -eq 0 ]]; then
            warning "IDs valides pour cette éxécution : $(getAllItemIDsCSV)"
            warning "Interactive mode: Aucun IDs valide dans operationsCSV; Aucun élément à afficher"
            showNoSelectableItemsDialog
            quitScript 0
        fi

        notice "Interactive mode : Limitation de la boîte de dialogue de sélection à ${#selectionDialogAllowedItemIDs[@]} éléments depuis operationsCSV"
    fi

    local baseMessage
    local warningMessage=""
    local messageText
    local dialogOutput
    local rc

    # Build message
    baseMessage="**Sélection des Apps à installer...**\n\nVeuillez séléctionner les éléments à installer ; Les casks et les formules Homebrew seront disponibles **une fois** que \`brew\` aura été installé."

    # Build unified checkbox list (Installomator + Jamf, sorted together by display name)
    getSelectionDialogCheckboxesJSON

    if [[ ${selectionDialogTotalItemCount} -eq 0 ]]; then
        showNoSelectableItemsDialog
        quitScript 0
    fi

    if [[ ${#selectionDialogOptionRecords[@]} -eq 0 ]]; then
        showNoSelectableItemsDialog
        quitScript 0
    fi

    # Loop until at least one item is selected
    while true; do
        messageText="${baseMessage}"
        if [[ -n "${warningMessage}" ]]; then
            messageText="${messageText}\n\n**${warningMessage}**"
        fi

        dialogOutput="$("${dialogBinary}" \
            --title "${humanReadableScriptName}" \
            --infotext "${scriptVersion}" \
            --messagefont "size=${fontSize}" \
            --message "${messageText}" \
            --icon "${mainDialogIcon}" \
            --jsonstring "{\"checkbox\":${selectionDialogCheckboxesJSON}}" \
            --checkboxstyle "switch,large" \
            --json \
            --button1text "Continue" \
            --button2text "Cancel" \
            --height "${dialogHeight}" \
            --width 900 2>/dev/null)"

        rc=$?
        if [[ ${rc} -eq 2 ]]; then
            info "User cancelled selection dialog"
            quitScript 0
        elif [[ ${rc} -ne 0 ]]; then
            errorOut "Selection dialog exited unexpectedly (return code: ${rc})"
            quitScript "${rc}"
        fi

        parseDialogSelections "${dialogOutput}"
        if [[ ${#selectedItems[@]} -gt 0 ]]; then
            notice "L'utilisateur a séléctionné ${#selectedItems[@]} éléments"
            return 0
        fi

        # Warn and retry if no selections
        warning "Aucun élément sélectionné dans la liste ; Nouvel affichage de la fenêtre de sélection"
        warningMessage="**:red[Warning:]** Veuillez sélectionner au moins _une_ option avant de cliquer sur **Continuer**."
    done
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Fonction formulaire nommage du poste O2I
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Afficher la fenêtre de bienvenue
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function displayWelcomeMessage() {

    requireLoggedInUser "display welcome form"
    
    local rc
    
    WelcomeStep="$(runAsUser "${loggedInUser}" "${dialogBinary}" \
        --title "${humanReadableScriptName}" \
        --infotext "${scriptVersion}" \
        --messagefont "size=${fontSize}" \
        --message "${messageWelcomeStep}" \
        --icon "${mainDialogIcon}" \
        --button1text "Continuer" \
        --button2text "Annuler" \
        --width 900 2>/dev/null)"
    
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        info "L'utilisateur a cliqué sur le bouton Continuer"
    else
        errorOut "L'utilisateur a cliqué sur le bouton Annuler (return code: ${rc})"
        quitScript "${rc}"
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Afficher le dialogue de nommage du poste
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function collectComputerName() {
    local formOutput rc
    local currentName
    currentName="$(/usr/sbin/scutil --get ComputerName 2>/dev/null)"

    requireLoggedInUser "display computer name form"

    while true; do
        formOutput="$(runAsUser "${loggedInUser}" "${dialogBinary}" \
            --title "${humanReadableScriptName}" \
            --infotext "${scriptVersion}" \
            --messagefont "size=${fontSize}" \
            --message "${messageComputerNameStep}" \
            --icon "${mainDialogIcon}" \
            --textfield "Nom du poste,name=computerName,required,value=${currentName}" \
            --selecttitle "Service",required \
            --selectvalues "Technique, Commercial, Administratif" \
            --button1text "Continuer" \
            --button2text "Annuler" \
            --json \
            --height 450 \
            --width 900 2>/dev/null)"
        rc=$?

        if [[ ${rc} -ne 0 ]]; then
            fatal "Saisie du nom de l'ordinateur annulée."
        fi

        computerName="$(print -r -- "${formOutput}" | /usr/bin/jq -r '.computerName // empty')"

        # validation simple : lettres, chiffres, tirets, 15 caractères max
        if [[ "${computerName}" =~ '^[A-Za-z0-9-]{1,15}$' ]]; then
            notice "Nom d'ordinateur saisi : ${computerName}"
            break
        fi
        warning "Nom d'ordinateur saisi éronné : '${computerName}'"
    done
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Fin des fonctions formulaire nommage du poste O2I
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Separate Selected Items by Type
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function separateSelectedItemsByType() {
    selectedInstallomatorLabels=()
    selectedJamfPolicies=()
    selectedHomebrewItems=()
    
    for itemID in "${selectedItems[@]}"; do
        local itemType
        itemType=$(getItemType "${itemID}")
        
        if [[ "${itemType}" == "installomator" ]]; then
            selectedInstallomatorLabels+=("${itemID}")
        elif [[ "${itemType}" == "jamf" ]]; then
            selectedJamfPolicies+=("${itemID}")
        elif [[ "${itemType}" == "homebrew" ]]; then
            selectedHomebrewItems+=("${itemID}")
        fi
    done
    
    info "Selections : ${#selectedInstallomatorLabels[@]} labels Installomator, ${#selectedJamfPolicies[@]} règles Jamf, ${#selectedHomebrewItems[@]} éléments Homebrew"
}



####################################################################################################
#
# Execution Engine Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Execute Installomator Label
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function executeInstallomatorLabel() {
    local label="$1"
    local validationPath="$2"
    local displayName="$3"
    local iconURL="$4"
    local installomatorExitCode
    local installomatorCheckPath=""
    local installomatorOwner=""
    local installomatorMode=""
    local subtitleSuffix=""

    # Check if already installed
    if [[ -n "${validationPath}" && -e "${validationPath}" ]]; then
        info "Skipping '${label}': ${validationPath} already exists"
        if [[ "${label}" == "homebrew" ]] && ! bootstrapHomebrewGitAfterLabel; then
            subtitleSuffix="; git est manquant, la mise à jour de brew est donc indisponible."
        fi
        skippedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "alreadyInstalled" "success" "${iconURL}" "Aucune action nécessaire ${subtitleSuffix}" "Déjà installé"
        return 0
    fi

    # Re-check ownership immediately before root executes Installomator (pre-flight check may be minutes old)
    if ! validateInstallomatorOwnership; then
        errorOut "Chemin Installomator ${installomatorCheckPath} Échec de la nouvelle vérification du propriétaire (${installomatorOwner}:${installomatorMode}) ; Ne fonctionne pas '${label}'"
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Veuillez contacter le support technique O2i si cette App est nécéssaire." "Non installé"
        return 1
    fi

    # Homebrew.pkg's postinstall needs git to leave a clean checkout, so Command Line Tools go first
    if [[ "${label}" == "homebrew" ]]; then
        bootstrapHomebrewGitBeforeLabel
    fi

    notice "Installing '${label}' (${displayName}) …"

    # Execute Installomator
    "${organizationInstallomatorFile}" "${label}" \
        DEBUG=0 NOTIFY=silent 2>&1 | while IFS= read -r installomatorOutputLine; do
            logComment "Installomator (${label}): ${installomatorOutputLine}"
        done
    installomatorExitCode=${pipestatus[1]}

    if [[ ${installomatorExitCode} -ne 0 ]]; then
        errorOut "Installomator a échoué pour '${label}' (code de sortie : ${installomatorExitCode})"
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Veuillez contacter le support technique O2i si cette App est nécéssaire." "Non installé"
        return 1
    else
        info "Installomator réussi pour '${label}'"
        if [[ "${label}" == "homebrew" ]] && ! bootstrapHomebrewGitAfterLabel; then
            subtitleSuffix=" ; git n'est pas installé, la commande brew update n'est donc pas disponible"
        fi
        completedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "installed" "success" "${iconURL}" "Prêt à utiliser ${subtitleSuffix}" "Installé"
        return 0
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Execute Jamf Policy
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function executeJamfPolicy() {
    local trigger="$1"
    local validationPath="$2"
    local displayName="$3"
    local iconURL="$4"
    local jamfExitCode
    
    # Check if already configured (validation path exists)
    if [[ -n "${validationPath}" && -e "${validationPath}" ]]; then
        info "Skipping policy '${trigger}': ${validationPath} already exists"
        skippedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "alreadyInstalled" "success" "${iconURL}" "Aucune action nécessaire" "Déjà installé"
        return 0
    fi
    
    notice "Éxécute la règle Jamf '${trigger}' (${displayName}) …"
    
    # Execute Jamf policy and log output
    "${jamfBinary}" policy -event "${trigger}" 2>&1 | while IFS= read -r jamfOutputLine; do
        logComment "Jamf (${trigger}): ${jamfOutputLine}"
    done
    jamfExitCode=${pipestatus[1]}

    # Post-execution validation
    if [[ ${jamfExitCode} -eq 0 ]]; then
        if [[ -n "${validationPath}" && -e "${validationPath}" ]]; then
            info "Règle Jamf '${trigger}' éxécutée avec succès et validée"
            completedItems+=("${displayName}")
            addCompletionReportRecord "${displayName}" "installed" "success" "${iconURL}" "Prêt à l'emploi" "Installé"
            return 0
        else
            warning "Règle Jamf '${trigger}' réussie mais le chemin de validation est introuvable : ${validationPath}"
            # Still mark as completed since jamf returned 0
            completedItems+=("${displayName}")
            addCompletionReportRecord "${displayName}" "needsReview" "error" "${iconURL}" "Installation réussie, mais impossible de confirmer entièrement le résultat" "À revoir"
            return 0
        fi
    else
        errorOut "Jamf policy '${trigger}' failed (exit code: ${jamfExitCode})"
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Veuillez contacter le support technique O2i si cette App est nécéssaire." "Non installé"
        return 1
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Homebrew Metadata (Optional)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateHomebrewMetadataIfNeeded() {
    local homebrewUpdateExitCode=0

    if [[ "${homebrewUpdateBeforeInstall:l}" != "true" ]]; then
        return 0
    fi

    if [[ "${homebrewUpdateAttempted}" == "true" ]]; then
        [[ "${homebrewUpdateSucceeded}" == "false" ]] && return 1
        return 0
    fi

    homebrewUpdateAttempted="true"

    # `brew update` needs git; skip it instead of failing every Homebrew item (bottle and cask installs still work)
    if ! resolveHomebrewGitPath; then
        warning "git introuvable ; Ignore la mise à jour de Brew (les métadonnées de Homebrew sont peut-être obsolètes)"
        homebrewUpdateSucceeded="skipped"
        return 0
    fi

    if ! refreshHomebrewExecutionUser; then
        errorOut "L'utilisateur Homebrew pour cette exécution n'est pas connecté ; Impossible de mettre à jour les métadonnées Homebrew"
        homebrewUpdateSucceeded="false"
        return 1
    fi

    setHomebrewCommandEnvironment

    notice "Mise à jour des métadonnées Homebrew en tant que ${loggedInUser} …"
    runAsUser "${loggedInUser}" "${homebrewCommandEnvironment[@]}" \
        "${effectiveBrewPath}" update 2>&1 | while IFS= read -r homebrewOutputLine; do
        logComment "Homebrew (update): ${homebrewOutputLine}"
    done
    homebrewUpdateExitCode=${pipestatus[1]}

    if [[ ${homebrewUpdateExitCode} -ne 0 ]]; then
        errorOut "Mise à jour Homebrew echouée (code de sortie : ${homebrewUpdateExitCode})"
        homebrewUpdateSucceeded="false"
        return 1
    fi

    info "Mise à jour des métadonnées Homebrew terminée"
    homebrewUpdateSucceeded="true"
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Ensure Homebrew Completion Directories
# Brew's completion child process can write into existing directories under share/ but can't create them
# (EPERM), so create them once per run as the Homebrew user (never root)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function ensureHomebrewCompletionDirectories() {
    local brewPrefix="${effectiveBrewPath:h:h}"
    local zshCompletionDirectory="${brewPrefix}/share/zsh/site-functions"
    local fishCompletionDirectory="${brewPrefix}/share/fish/vendor_completions.d"
    local mkdirExitCode=0

    if [[ "${homebrewCreateCompletionDirectories:l}" != "true" ]]; then
        return 0
    fi

    if [[ "${homebrewCompletionDirectoriesAttempted}" == "true" ]]; then
        return 0
    fi

    homebrewCompletionDirectoriesAttempted="true"

    if [[ -d "${zshCompletionDirectory}" && -d "${fishCompletionDirectory}" ]]; then
        return 0
    fi

    info "Création de répertoires de complétion Homebrew sous ${brewPrefix}/share en tant que ${loggedInUser} …"
    runAsUser "${loggedInUser}" /bin/mkdir -p "${zshCompletionDirectory}" "${fishCompletionDirectory}" 2>&1 | while IFS= read -r mkdirOutputLine; do
        logComment "Homebrew (completions): ${mkdirOutputLine}"
    done
    mkdirExitCode=${pipestatus[1]}

    if [[ ${mkdirExitCode} -ne 0 ]]; then
        warning "Impossible de créer les répertoires de complétion Homebrew sous ${brewPrefix}/share (code de sortie : ${mkdirExitCode}); il se peut que certaines complétion du shell manquent"
        return 1
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Install Command Line Tools (Optional)
# Supplies git for Homebrew and the user's shell when none is found; runs as root via softwareupdate,
# so no logged-in user, admin rights, or prompts are needed. Once per run; never aborts the run.
# Adapted from Rich Trouton's install_xcode_command_line_tools.sh (macOS 10.15+ branch only)
# https://github.com/rtrouton/rtrouton_scripts/tree/main/rtrouton_scripts/install_xcode_command_line_tools
# Returns: 0 if git is available (or the setting is disabled), 1 otherwise
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function installCommandLineTools() {
    local softwareUpdateList=""
    local commandLineToolsLabel=""
    local softwareUpdateExitCode=0
    local stepStartSeconds=0

    if [[ "${homebrewAutoInstallCommandLineTools:l}" != "true" ]]; then
        return 0
    fi

    if resolveHomebrewGitPath; then
        return 0
    fi

    if [[ "${commandLineToolsAttempted}" == "true" ]]; then
        return 1
    fi

    commandLineToolsAttempted="true"

    notice "git introuvable ; Installation des outils de ligne de commande..."

    # The trigger file makes softwareupdate list Command Line Tools. /tmp is world-writable, so never follow
    # an existing (possibly user-planted) path as root: remove it, create exclusively, then verify
    rm -f -- "${commandLineToolsTriggerFile}" 2>/dev/null
    if ! ( setopt NO_CLOBBER; : > "${commandLineToolsTriggerFile}" ) 2>/dev/null; then
        warning "Impossible de créer ${commandLineToolsTriggerFile} ; Ignore l'installation des outils de ligne de commande"
        return 1
    fi
    commandLineToolsTriggerFileCreated="true"

    if [[ -L "${commandLineToolsTriggerFile}" || ! -f "${commandLineToolsTriggerFile}" || ! -O "${commandLineToolsTriggerFile}" ]]; then
        warning "${commandLineToolsTriggerFile} n'est pas un fichier appartenant à l'utilisateur root ; Ignore l'installation des outils de ligne de commande"
        commandLineToolsTriggerFileCreated="false"
        return 1
    fi

    # Stream scan output to the log as it arrives (the scan can be quiet for a minute or more) and keep it for parsing
    info "Verification de softwareupdate pour les outils en ligne de commande (cela peut prendre une minute ou plus)..."
    stepStartSeconds=${SECONDS}
    /usr/sbin/softwareupdate --list 2>&1 | while IFS= read -r softwareUpdateOutputLine; do
        softwareUpdateList+="${softwareUpdateOutputLine}"$'\n'
        [[ -n "${softwareUpdateOutputLine//[[:space:]]/}" ]] && logComment "softwareupdate (CLT scan): ${softwareUpdateOutputLine}"
    done
    info "Scan softwareupdate terminé en $(( SECONDS - stepStartSeconds )) secondes"

    # Newest non-beta label; version-aware sort so 26.10 ranks above 26.9
    commandLineToolsLabel="$( print -r -- "${softwareUpdateList}" \
        | /usr/bin/grep -E '^[[:space:]]*\* Label: Command Line Tools' \
        | /usr/bin/grep -vi 'beta' \
        | /usr/bin/sed -E 's/^[[:space:]]*\* Label: //; s/[[:space:]]+$//' \
        | /usr/bin/sort -V \
        | /usr/bin/tail -n 1 )"

    if [[ -z "${commandLineToolsLabel}" ]]; then
        rm -f -- "${commandLineToolsTriggerFile}" 2>/dev/null
        commandLineToolsTriggerFileCreated="false"
        warning "Aucun outil en ligne de commande n'a été trouvé dans softwareupdate (hors ligne, CDN Apple bloqué ou mises à jour différées); Homebrew fonctionne sans git"
        return 1
    fi

    notice "Installe '${commandLineToolsLabel}' via softwareupdate (téléchargement volumineux ; cela peut prendre plusieurs minutes) …"
    stepStartSeconds=${SECONDS}
    /usr/sbin/softwareupdate --install "${commandLineToolsLabel}" --verbose 2>&1 | /usr/bin/tr '\r' '\n' | while IFS= read -r softwareUpdateOutputLine; do
        [[ -n "${softwareUpdateOutputLine//[[:space:]]/}" ]] && logComment "softwareupdate (CLT): ${softwareUpdateOutputLine}"
    done
    softwareUpdateExitCode=${pipestatus[1]}

    rm -f -- "${commandLineToolsTriggerFile}" 2>/dev/null
    commandLineToolsTriggerFileCreated="false"

    if [[ ${softwareUpdateExitCode} -ne 0 ]]; then
        warning "softwareupdate a echoué à installer '${commandLineToolsLabel}' après $(( SECONDS - stepStartSeconds )) secondes (exit code: ${softwareUpdateExitCode}) ; Homebrew fonctionne sans Git"
        return 1
    fi

    info "softwareupdate a fini d'installer '${commandLineToolsLabel}' en $(( SECONDS - stepStartSeconds )) secondes"

    if ! /usr/bin/xcode-select -print-path >/dev/null 2>&1; then
        info "Section de /Library/Developer/CommandLineTools en tant que répertoire de développement actif"
        /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools 2>&1 | while IFS= read -r xcodeSelectOutputLine; do
            logComment "xcode-select: ${xcodeSelectOutputLine}"
        done
    fi

    if ! resolveHomebrewGitPath; then
        warning "softwareupdate a installé '${commandLineToolsLabel}', mais git introuvable ; Homebrew fonctionne sans git"
        return 1
    fi

    info "Outils de ligne de commande installés ; git se trouve ${homebrewGitPath}"
    logHomebrewVersion
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Log Homebrew Version
# Once per run, when brew exists and the pinned Homebrew user is still logged in (brew refuses root).
# `-dirty` means tracked files in the Homebrew checkout differ from HEAD; Homebrew.pkg's postinstall
# resets its checkout only when Command Line Tools `git` is already installed
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function logHomebrewVersion() {
    local homebrewVersion=""

    if [[ "${homebrewVersionLogged}" == "true" ]]; then
        return 0
    fi

    if [[ -z "${effectiveBrewPath}" || ! -x "${effectiveBrewPath}" || -z "${homebrewExecutionUser}" ]]; then
        return 0
    fi

    if ! refreshHomebrewExecutionUser; then
        return 0
    fi

    homebrewVersionLogged="true"
    setHomebrewCommandEnvironment
    homebrewVersion="$( runAsUser "${loggedInUser}" "${homebrewCommandEnvironment[@]}" "${effectiveBrewPath}" --version 2>/dev/null | /usr/bin/head -n 1 )"

    if [[ "${homebrewVersion}" == *-dirty ]]; then
        warning "${homebrewVersion}: Le dépôt Homebrew contient des modifications locales (probablement installées avant que git ne soit disponible); en tant que ${loggedInUser}, lance 'brew update-reset'"
    elif [[ -n "${homebrewVersion}" ]]; then
        info "${homebrewVersion}"
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Bootstrap git Before Installomator `homebrew` Label
# Homebrew.pkg's postinstall resets its git checkout (`reset --hard`, `clean -f -d`) only when
# `xcode-select -print-path` has `git`; without it, brew reports `-dirty`. Install Command Line Tools first.
# Brew is not installed yet, so no Homebrew user is needed
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function bootstrapHomebrewGitBeforeLabel() {
    if [[ "${enableHomebrewItems:l}" != "true" ]]; then
        return 0
    fi

    installCommandLineTools
    markCommandLineToolsInspectItemComplete
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Bootstrap git After Installomator `homebrew` Label
# Runs after the label installs or skips Homebrew, so an existing Homebrew without git gets it too
# (Command Line Tools alone don't clean an already-dirty checkout); logs `brew --version`
# Returns: 0 if git is available (or Homebrew items are disabled or brew is missing), 1 if git is still missing
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function bootstrapHomebrewGitAfterLabel() {
    local previousLoggedInUser="${loggedInUser}"

    if [[ "${enableHomebrewItems:l}" != "true" ]]; then
        return 0
    fi

    # Pre-flight leaves effectiveBrewPath empty when Homebrew was missing (or no Homebrew items are configured)
    if [[ -z "${effectiveBrewPath}" ]]; then
        effectiveBrewPath="$(detectHomebrewBinary)"
    fi

    if [[ -z "${effectiveBrewPath}" ]]; then
        return 0
    fi

    # Pin the Homebrew user if pre-flight couldn't; Command Line Tools install itself needs no user
    if [[ -z "${homebrewExecutionUser}" ]]; then
        if refreshHomebrewExecutionUser; then
            homebrewExecutionUser="${loggedInUser}"
        else
            loggedInUser="${previousLoggedInUser}"
        fi
    fi

    installCommandLineTools
    markCommandLineToolsInspectItemComplete
    logHomebrewVersion

    if ! resolveHomebrewGitPath; then
        if [[ "${homebrewAutoInstallCommandLineTools:l}" != "true" ]]; then
            warning "git introuvable ; mise à jour brew et taps tierces partie indisponible (homebrewAutoInstallCommandLineTools=false)"
        fi
        return 1
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Trust Homebrew Item (Optional)
# Input: Homebrew item ID, brew mode (cask|formula), brew token
# Only fully-qualified third-party tokens (`user/tap/name`) need trust; official taps are always trusted
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function trustHomebrewItemIfNeeded() {
    local homebrewID="$1"
    local brewMode="$2"
    local brewToken="$3"
    local homebrewTrustExitCode=0

    if [[ "${homebrewAutoTrustItems:l}" != "true" ]]; then
        return 0
    fi

    if [[ ! "${brewToken}" =~ ^[^/]+/[^/]+/[^/]+$ || "${brewToken:l}" == homebrew/* ]]; then
        return 0
    fi

    setHomebrewCommandEnvironment

    info "Confiance accordée à Homebrew ${brewMode} '${brewToken}' for ${loggedInUser} …"
    runAsUser "${loggedInUser}" "${homebrewCommandEnvironment[@]}" \
        "${effectiveBrewPath}" trust "--${brewMode}" "${brewToken}" 2>&1 | while IFS= read -r homebrewOutputLine; do
        logComment "Homebrew (confiance :${homebrewID}): ${homebrewOutputLine}"
    done
    homebrewTrustExitCode=${pipestatus[1]}

    if [[ ${homebrewTrustExitCode} -ne 0 ]]; then
        warning "Échec de la vérification de la confiance Homebrew pour '${homebrewID}' (code de sortie : ${homebrewTrustExitCode}) ; tente quand même l'installation"
        return 1
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Remove Homebrew Quarantine (Optional)
# Input: Homebrew item ID, brew mode (cask|formula), resolved validation path
# Only cask `.app` bundles; quarantine is removed as the logged-in user only after Gatekeeper accepts the app
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function removeHomebrewQuarantineIfNeeded() {
    local homebrewID="$1"
    local brewMode="$2"
    local targetPath="$3"
    local gatekeeperAssessment=""
    local gatekeeperExitCode=0
    local quarantineExitCode=0

    if [[ "${homebrewAutoRemoveQuarantine:l}" != "true" ]]; then
        return 0
    fi

    if [[ "${brewMode}" != "cask" || "${targetPath}" != *.app ]]; then
        return 0
    fi

    if [[ -L "${targetPath}" || ! -d "${targetPath}" ]]; then
        warning "Non-levée de la quarantaine pour '${homebrewID}': ${targetPath} n'est pas un répertoire de paquets d'applications"
        return 1
    fi

    if ! /usr/bin/xattr -p com.apple.quarantine "${targetPath}" >/dev/null 2>&1; then
        info "Aucun indicateur de quarantaine sur ${targetPath}"
        return 0
    fi

    gatekeeperAssessment="$( /usr/sbin/spctl --assess --type execute --verbose=2 "${targetPath}" 2>&1 )"
    gatekeeperExitCode=$?

    if [[ ${gatekeeperExitCode} -ne 0 ]]; then
        warning "Gatekeeper a rejeté '${homebrewID}' (${targetPath}); mis en quarantaine : ${gatekeeperAssessment//$'\n'/ }"
        return 1
    fi

    info "Gatekeeper a accepté '${homebrewID}': ${gatekeeperAssessment//$'\n'/ }"

    runAsUser "${loggedInUser}" /usr/bin/xattr -drs com.apple.quarantine "${targetPath}" 2>&1 | while IFS= read -r quarantineOutputLine; do
        logComment "Homebrew (quarantine:${homebrewID}): ${quarantineOutputLine}"
    done
    quarantineExitCode=${pipestatus[1]}

    if [[ ${quarantineExitCode} -ne 0 ]]; then
        warning "La suppression de la quarantaine a échoué pour '${homebrewID}' (code de sortie : ${quarantineExitCode})"
        return 1
    fi

    info "Suppression du drapeau de quarantaine de ${targetPath}"
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Execute Homebrew Item
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function executeHomebrewItem() {
    local homebrewID="$1"
    local brewMode="$2"
    local brewToken="$3"
    local validationPath="$4"
    local displayName="$5"
    local iconURL="$6"
    local homebrewExitCode=0
    local homebrewSudoBlocked="false"
    local homebrewWarningDetected="false"
    local homebrewWarningDetail=""
    local userApplicationsDirectory=""
    local -a brewCommand=()

    if [[ -n "${validationPath}" && -e "${validationPath}" ]]; then
        info "Ignore l'élément Homebrew '${homebrewID}': ${validationPath} existe déjà"
        skippedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "alreadyInstalled" "success" "${iconURL}" "Aucune action necessaire" "Déjà installé"
        return 0
    fi

    if [[ -z "${effectiveBrewPath}" || ! -x "${effectiveBrewPath}" ]]; then
        errorOut "Éléments Homebrew '${homebrewID}' Impossible d'exécuter le programme car aucun binaire Brew fonctionnel n'est disponible"
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Homebrew n'est pas installé ou n'est pas exécutable" "Non installé"
        return 1
    fi

    if ! refreshHomebrewExecutionUser; then
        errorOut "Élément Homebrew '${homebrewID}' ne peux pas exécuter le programme car l'utilisateur Homebrew associé à cette session n'est pas connecté"
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Pour les installations via Homebrew, l'utilisateur doit rester connecté." "Non installé"
        return 1
    fi

    installCommandLineTools
    markCommandLineToolsInspectItemComplete

    if ! updateHomebrewMetadataIfNeeded; then
        failedItems+=("${displayName}")
        addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Échec de la mise à jour des métadonnées de Homebrew" "Non installé"
        return 1
    fi

    ensureHomebrewCompletionDirectories

    trustHomebrewItemIfNeeded "${homebrewID}" "${brewMode}" "${brewToken}"

    setHomebrewCommandEnvironment
    brewCommand=(
        "${homebrewCommandEnvironment[@]}"
        HOMEBREW_NO_AUTO_UPDATE=1
        "${effectiveBrewPath}"
        install
    )

    if [[ "${brewMode}" == "cask" ]]; then
        brewCommand+=(--cask)

        # Non-admin users can't write to /Applications; install apps to ~/Applications instead of prompting for sudo
        if [[ "${loggedInUserIsAdmin}" == "false" ]]; then
            userApplicationsDirectory="${loggedInUserHomeDirectory}/Applications"
            runAsUser "${loggedInUser}" /bin/mkdir -p "${userApplicationsDirectory}"
            brewCommand+=("--appdir=${userApplicationsDirectory}")
            info "${loggedInUser} n'est pas un administrateur'; Installation de '${brewToken}' dans ${userApplicationsDirectory}"
        fi
    fi

    brewCommand+=("${brewToken}")

    notice "Installation de Homebrew ${brewMode} '${brewToken}' (${displayName}) en tant que ${loggedInUser} …"

    runAsUser "${loggedInUser}" "${brewCommand[@]}" 2>&1 | while IFS= read -r homebrewOutputLine; do
        logComment "Homebrew (${homebrewID}): ${homebrewOutputLine}"
        [[ "${homebrewOutputLine}" == *HOMEBREW_NO_SUDO* ]] && homebrewSudoBlocked="true"

        # Brew can exit 0 after a child process fails (e.g., shell completions under ${homebrewPrefix}/share)
        case "${homebrewOutputLine}" in
            *"Operation not permitted"*|*"Permission denied"*)
                homebrewWarningDetected="true"
                if [[ -z "${homebrewWarningDetail}" ]]; then
                    homebrewWarningDetail="${homebrewOutputLine#"${homebrewOutputLine%%[^[:space:]]*}"}"
                fi
                ;;
            *"An exception occurred within a child process"*)
                homebrewWarningDetected="true"
                ;;
        esac
    done
    homebrewExitCode=${pipestatus[1]}

    if [[ ${homebrewExitCode} -ne 0 ]]; then
        failedItems+=("${displayName}")
        if [[ "${homebrewSudoBlocked}" == "true" ]]; then
            errorOut "Homebrew install failed for '${homebrewID}' (exit code: ${homebrewExitCode}); package requires administrator privileges"
            addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Necesite des droits administrateurs; Veuillez contacter le support O2i" "Non installé"
        else
            errorOut "Homebrew install failed for '${homebrewID}' (exit code: ${homebrewExitCode})"
            addCompletionReportRecord "${displayName}" "notInstalled" "fail" "${iconURL}" "Veuillez contacter le support O2i si ce package est nécessaire" "Non installé"
        fi
        return 1
    fi

    if [[ "${homebrewWarningDetected}" == "true" ]]; then
        warning "Homebrew a signalé des erreurs pour '${homebrewID}' malgré un code de sortie égal à 0 ; il se peut que certaines complétions du shell ou d'autres fonctionnalités supplémentaires manquent ${homebrewWarningDetail:+: ${homebrewWarningDetail}}"
    fi

    if [[ -n "${validationPath}" && -e "${validationPath}" ]]; then
        info "Installation de Homebrew réussie et validée pour '${homebrewID}'"
        removeHomebrewQuarantineIfNeeded "${homebrewID}" "${brewMode}" "${validationPath}"
        completedItems+=("${displayName}")
        if [[ "${homebrewWarningDetected}" == "true" ]]; then
            addCompletionReportRecord "${displayName}" "installed" "success" "${iconURL}" "Prêts à utiliser ; Avertissements signalés par Homebrew" "Installé"
        else
            addCompletionReportRecord "${displayName}" "installed" "success" "${iconURL}" "Prêt à l'emploi" "Installé"
        fi
        return 0
    fi

    warning "Installation Homebrew de '${homebrewID}' terminée, mais chemin de validation introuvable : ${validationPath}"
    completedItems+=("${displayName}")
    addCompletionReportRecord "${displayName}" "needsReview" "error" "${iconURL}" "Installé, mais nous n'avons pas pu confirmer entièrement le résultat" "À revoir"
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Unified Execution Dispatcher
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function executeSYMLiteItems() {
    notice "Lancement de l'exécution des ${#selectedItems[@]} éléments sélectionnés"
    completionReportRecords=()

    if [[ ${#selectedItems[@]} -eq 0 ]]; then
        errorOut "Aucun élément sélectionné n'est disponible pour installation"
        return 1
    fi
    
    if [[ "${operationMode}" != "silent" ]]; then
        requireLoggedInUser "launch Inspect Mode"

        # Create Inspect Mode configuration
        notice "Création d'une configuration du mode d'inspection..."
        if ! createSYMLiteInspectConfig; then
            fatal "Échec de la création de la configuration du mode d'inspection"
        fi

        prepareInspectConfigForUser

        # Launch Dialog in background for real-time progress
        notice "Lancement de dialog en mode inspection..."
        createDialogCommandFile
        if ! launchAsUserInBackground "${loggedInUser}" /usr/bin/env DIALOG_INSPECT_CONFIG="${dialogInspectModeJSONFile}" "${dialogBinary}" --commandfile "${dialogCommandFile}" --inspect-mode; then
            fatal "Impossible de démarrer dialog en mode inspection"
        fi
        info "PID du mode inspection : ${dialogPID}"

        # Give dialog a moment to launch
        sleep 2
    else
        info "Mode silencieux activé; Ignore le mode inspection UI"
    fi
    
    # Process each selected item sequentially
    for itemID in "${selectedItems[@]}"; do
        local itemType
        itemType=$(getItemType "${itemID}")
        
        local itemConfig
        itemConfig=$(getItemConfig "${itemID}")
        
        if [[ "${itemType}" == "installomator" ]]; then
            parseInstallomatorItem "${itemConfig}"
            executeInstallomatorLabel "${itemLabel}" "${itemValidationPath}" "${itemDisplayName}" "${itemIconURL}"
        elif [[ "${itemType}" == "jamf" ]]; then
            parseJamfPolicyItem "${itemConfig}"
            executeJamfPolicy "${itemTrigger}" "${itemValidationPath}" "${itemDisplayName}" "${itemIconURL}"
        elif [[ "${itemType}" == "homebrew" ]]; then
            parseHomebrewItem "${itemConfig}"
            executeHomebrewItem "${itemHomebrewID}" "${itemBrewMode}" "${itemBrewToken}" "${itemValidationPath}" "${itemDisplayName}" "${itemIconURL}"
        else
            warning "Type d'élément inconnu pour l'ID : ${itemID}"
        fi
    done
    
    if [[ -n "${dialogPID}" ]]; then
        # Wait for Dialog to close (with timeout)
        info "En attente de la fermeture du mode inspection (PID: ${dialogPID})..."
        local waitCount=0
        local maxWait=30
        while kill -0 "${dialogPID}" 2>/dev/null && (( waitCount < maxWait )); do
            sleep 1
            ((waitCount++))
        done

        if kill -0 "${dialogPID}" 2>/dev/null; then
            warning "Dialog ne s'est pas arrêté après ${maxWait} secondes; demande de sortie."
            closeInspectMode "Délai d'attente dépassé pour Continuer"
        fi

        dialogPID=""
        removeDialogCommandFile
        info "Mode inspection fermé."
    fi
    
    notice "Execution terminée : ${#completedItems[@]} réussis, ${#skippedItems[@]} ignorés, ${#failedItems[@]} échoués"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Interruption Handler
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function handleInterruption() {
    warning "Script interrompu par l'utilisateur"
    
    if [[ -n "${dialogPID}" || ( -n "${dialogCommandFile}" && -e "${dialogCommandFile}" ) ]]; then
        closeInspectMode "interrupt"
    fi
    
    cleanup
    exit 130
}

trap handleInterruption SIGINT SIGTERM



####################################################################################################
#
# Completion and Restart Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Completion Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function showCompletionDialog() {
    requireLoggedInUser "display completion dialog"

    local installedCount=0
    local alreadyInstalledCount=0
    local needsReviewCount=0
    local notInstalledCount=0
    local record=""
    local displayName=""
    local statusKey=""
    local dialogStatus=""
    local iconURL=""
    local subtitle=""
    local statusText=""
    local dialogTitle=""
    local dialogIcon=""
    local dialogMessage="Voici le statut des éléments que vous avez sélectionnés, ${loggedInUserFirstname}.\n\n"
    local listItemsJSON=""
    local completionDialogJSON=""
    local jsonValidationError=""
    local retryCount=0
    local maxRetries=5

    for record in "${completionReportRecords[@]}"; do
        IFS=$'\t' read -r displayName statusKey dialogStatus iconURL subtitle statusText <<< "${record}"

        case "${statusKey}" in
            installed )
                ((installedCount++))
                ;;
            alreadyInstalled )
                ((alreadyInstalledCount++))
                ;;
            needsReview )
                ((needsReviewCount++))
                ;;
            notInstalled )
                ((notInstalledCount++))
                ;;
        esac
    done

    if [[ ${notInstalledCount} -gt 0 ]]; then
        dialogTitle="Terminé avec des erreurs"
        dialogIcon="SF=xmark.octagon.fill,weight=bold,colour1=#EB5545,colour2=#A61E16"
    elif [[ ${needsReviewCount} -gt 0 ]]; then
        dialogTitle="Terminé avec des alertes"
        dialogIcon="SF=exclamationmark.triangle.fill,weight=bold,colour1=#F8D84A,colour2=#D18E00"
    else
        dialogTitle="Terminé avec succès"
        dialogIcon="SF=checkmark.circle.fill,weight=bold,colour1=#63CA56,colour2=#2D7D2B"
    fi

    [[ ${installedCount} -gt 0 ]] && dialogMessage="${dialogMessage}**${installedCount}** installé et prêt à l'emploi.\n"
    [[ ${alreadyInstalledCount} -gt 0 ]] && dialogMessage="${dialogMessage}**${alreadyInstalledCount}** déjà installé.\n"
    [[ ${needsReviewCount} -gt 0 ]] && dialogMessage="${dialogMessage}**${needsReviewCount}** à vérifier.\n"
    [[ ${notInstalledCount} -gt 0 ]] && dialogMessage="${dialogMessage}**${notInstalledCount}** non installé.\n"

    listItemsJSON=$(buildCompletionReportListItemsJSON)

    createDialogRuntimeDirectory

    completionDialogJSONFile="${dialogRuntimeDirectory}/completionConfig.json"
    if ! : > "${completionDialogJSONFile}" 2>/dev/null; then
        completionDialogJSONFile=""
        fatal "Échec de la création du fichier JSON de complétion dialog"
    fi

    completionDialogJSON="{
    \"title\": \"$(escapeJSONString "${dialogTitle}")\",
    \"message\": \"$(escapeJSONString "${dialogMessage}")\",
    \"icon\": \"$(escapeJSONString "${dialogIcon}")\",
    \"button1text\": \"Close\",
    \"infotext\": \"$(escapeJSONString "${scriptVersion}")\",
    \"height\": ${dialogHeight},
    \"width\": 900,
    \"messagefont\": \"size=${fontSize}\",
    \"listitem\": ${listItemsJSON}
}"

    if ! /bin/cat > "${completionDialogJSONFile}" <<EOF
${completionDialogJSON}
EOF
    then
        rm -f -- "${completionDialogJSONFile}" 2>/dev/null
        completionDialogJSONFile=""
        fatal "Echec de création du fichier JSON dialog"
    fi

    jsonValidationError=$(/usr/bin/plutil -convert json -o /dev/null "${completionDialogJSONFile}" 2>&1)
    if [[ $? -ne 0 ]]; then
        rm -f -- "${completionDialogJSONFile}" 2>/dev/null
        completionDialogJSONFile=""
        fatal "Le fichier JSON de dialog est malformé : ${jsonValidationError}"
    fi

    prepareCompletionDialogConfigForUser

    while [[ ! -f "${completionDialogJSONFile}" || ! -r "${completionDialogJSONFile}" ]] && [[ ${retryCount} -lt ${maxRetries} ]]; do
        sleep 0.2
        ((retryCount++))
    done

    if [[ ! -f "${completionDialogJSONFile}" || ! -r "${completionDialogJSONFile}" ]]; then
        local unreadableCompletionDialogJSONFile="${completionDialogJSONFile}"
        rm -f -- "${completionDialogJSONFile}" 2>/dev/null
        completionDialogJSONFile=""
        fatal "Le fichier JSON de dialog (${unreadableCompletionDialogJSONFile}) est illisible après ${maxRetries} tentatives"
    fi

    runAsUser "${loggedInUser}" "${dialogBinary}" --jsonfile "${completionDialogJSONFile}" 2>/dev/null

    rm -f -- "${completionDialogJSONFile}" 2>/dev/null
    completionDialogJSONFile=""

    notice "La fenêtre dialog fermée"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Restart Helpers
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Restarts only through loginwindow as the logged-in user, so apps can prompt to save and the user can cancel
function executeRestartAction() {
    currentLoggedInUser "false"

    if isSystemConsoleUser "${loggedInUser}" || ! /usr/bin/id -u "${loggedInUser}" >/dev/null 2>&1; then
        warning "Aucun utilisateur valide connecté à l'interface graphique n'a été détécté ; commande 'Restart Confirm' non déclenchée."
        return 1
    fi

    if runAsUser "${loggedInUser}" /usr/bin/osascript -e 'tell app "loginwindow" to «event aevtrrst»' >>"${scriptLog}" 2>&1; then
        notice "Commande 'Restart Confirm' déclenchée par ${loggedInUser}."
        return 0
    fi

    warning "Echec de déclenchement de la commande de redémarrage 'Restart Confirm' pour l'utilisateur ${loggedInUser}."
    return 1
}

function promptForRestart() {
    if [[ "${restartPromptEnabled}" != "true" ]] || [[ "${operationMode}" == "silent" ]]; then
        return 0
    fi

    requireLoggedInUser "display restart prompt"
    
    local rc
    local restartFontSize=$(( fontSize > 2 ? fontSize - 2 : fontSize ))
    
    "${dialogBinary}" \
        --title "Redémarrage recommandé" \
        --infotext "${scriptVersion}" \
        --messagefont "size=${restartFontSize}" \
        --message "**Un redémarrage peut être recommandé après l'installation d'un logiciel ou l'application de ces modifications.**\n\nSouhaitez-vous redémarrer maintenant ?" \
        --icon "SF=restart.circle.fill,colour=#969899" \
        --buttonstyle "stack" \
        --hidedefaultkeyboardaction \
        --button1text "Redémarrer maintenant" \
        --button2text "Plus tard" \
        --height 400 \
        --width 400 2>/dev/null
    
    rc=$?
    
    if [[ ${rc} -eq 0 ]]; then
        notice "L'utilisateur a choisi de redémarrer maintenant."
        executeRestartAction
    else
        notice "L'utilisateur a choisi de redémarrer plus tard."
    fi
}



####################################################################################################
#
# Main Program
#
####################################################################################################

notice "SYM-Lite démarré avec succès"
notice "Configuration : ${#installomatorLabels[@]} labels Installomator, ${#jamfPolicyItems[@]} règles Jamf, ${#homebrewItems[@]} éléments Homebrew"
if [[ "${enableJamfPolicyItems:l}" != "true" ]]; then
    notice "Les règles Jamf sont désactivées dans la configuration"
fi
if [[ "${enableHomebrewItems:l}" != "true" ]]; then
    notice "Les éléments Homebrew sont désactivées dans la configuration"
fi
notice "Operation mode : ${operationMode}"

###############################################################
############################# O2I #############################
###############################################################

# Phase 0 : Affichage du message de bienvenue
displayWelcomeMessage

# Phase 1: Show computer name form and apply the name
collectComputerName

# Nommage du poste
/usr/sbin/scutil --set ComputerName "${computerName}"
/usr/sbin/scutil --set LocalHostName "${computerName}"
/usr/sbin/scutil --set HostName "${computerName}"

###############################################################
############################# O2I #############################
###############################################################

# Phase 2: Show selection dialog
if ! showSelectionDialog; then
    fatal "Aucune action valide n'a été sélectionnée ; sortie."
fi
separateSelectedItemsByType

# Phase 3 & 4: Execute selected items via Inspect Mode
if ! executeSYMLiteItems; then
    fatal "Impossible d'exécuter les éléments sélectionnés."
fi

# Phase 5: Display completion and prompt for restart
if [[ "${operationMode}" == "silent" ]]; then
    info "Mode silencieux activé ; omission de la boîte de dialogue de validation et de l'invite de redémarrage"
else
    if [[ ${#completedItems[@]} -eq 0 && ${#failedItems[@]} -eq 0 ]]; then
        notice "Les ${#skippedItems[@]} éléments séléctionnés  etaient déjà installés ; Affiche le rapport de fin sans invite de redémarrage."
    fi

    showCompletionDialog

    if [[ ${#completedItems[@]} -eq 0 && ${#failedItems[@]} -eq 0 ]]; then
        info "Ignore l'invite de redémarrage car tous les éléments sélectionnés étaient déjà installés."
    else
        promptForRestart
    fi
fi

info "Éxécution de SYM-Lite terminée - Temps total écoulé : $(formattedElapsedTime)"

if [[ ${#failedItems[@]} -gt 0 ]]; then
    errorOut "${#failedItems[@]} item(s) failed: ${(j:, :)failedItems}"
    quitScript 1
fi

quitScript 0
