Unicode true
ManifestDPIAware true
SetCompressor lzma
RequestExecutionLevel user

!define "__check_${NSIS_MAX_STRLEN}"
!ifndef "__check_8192"
  !error "'strlen_8192' build is required to compile this script (see 'NSIS-upgrade.md'). NSIS_MAX_STRLEN=${NSIS_MAX_STRLEN}."
!endif
!undef "__check_${NSIS_MAX_STRLEN}"

!addplugindir "${NSIS_DIR}\Plugins\x86-unicode"
!addincludedir "${NSIS_DIR}\Include"

!include FileFunc.nsh
!include InstallOptions.nsh
!include LogicLib.nsh
!include MUI2.nsh
!include StrFunc.nsh
!include TextFunc.nsh
!include UAC.nsh
!include WinVer.nsh
!include x64.nsh

; `StrFunc.nsh` requires priming the commands which actually get used later
${StrStr}
${UnStrStr}
${StrLoc}
${UnStrRep}

!include "log.nsi"
!include "registry.nsi"
!include "config.nsi"
!include "customInstallActions.nsi"

Name "${MUI_PRODUCT}"

!define /date CURRENT_YEAR "%Y"
VIAddVersionKey /LANG=0 "CompanyName" "JetBrains s.r.o."
VIAddVersionKey /LANG=0 "FileDescription" "${MUI_PRODUCT} Windows Installer"
VIAddVersionKey /LANG=0 "LegalCopyright" "Copyright 2000-${CURRENT_YEAR} JetBrains s.r.o."
VIAddVersionKey /LANG=0 "ProductName" "${MUI_PRODUCT}"
VIAddVersionKey /LANG=0 "ProductVersion" "${MUI_VERSION_MAJOR}.${MUI_VERSION_MINOR}"
VIFileVersion ${FILE_VERSION_NUM}
VIProductVersion ${PRODUCT_VERSION_NUM}

; Product with version (IntelliJ IDEA #xxxx).
; Used in registry to put each build info into the separate subkey
; Add&Remove programs doesn't understand subkeys in the Uninstall key,
; thus ${PRODUCT_WITH_VER} is used for uninstall registry information
!define PRODUCT_REG_VER "${MUI_PRODUCT}\${VER_BUILD}"

Var startMenuFolder
Var productLauncher
Var baseRegKey
Var silentMode
Var requiredDiskSpace

; position of controls for Uninstall Old Installations dialog
Var control_fields
Var max_fields
Var bottom_position
Var max_length
Var line_width
Var extra_space

; position of controls for Installation Options dialog
Var launcherShortcut
Var addToPath
Var updateContextMenu

ReserveFile "desktop.ini"
ReserveFile "DeleteSettings.ini"
ReserveFile "UninstallOldVersions.ini"
!insertmacro MUI_RESERVEFILE_LANGDLL

!define MUI_ICON "${IMAGES_LOCATION}\${PRODUCT_ICON_FILE}"
!define MUI_UNICON "${IMAGES_LOCATION}\${PRODUCT_UNINSTALL_ICON_FILE}"

!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${IMAGES_LOCATION}\${PRODUCT_HEADER_FILE}"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${IMAGES_LOCATION}\${PRODUCT_LOGO_FILE}"

!define MUI_CUSTOMFUNCTION_GUIINIT GUIInit


!macro INST_UNINST_SWITCH un
  Function ${un}SplitStr
    Exch $0 ; str
    Push $1 ; inQ
    Push $3 ; idx
    Push $4 ; tmp
    StrCpy $1 0
    StrCpy $3 0
  loop:
    StrCpy $4 $0 1 $3
    ${If} $4 == '"'
      ${If} $1 <> 0
        StrCpy $0 $0 "" 1
        IntOp $3 $3 - 1
      ${EndIf}
      IntOp $1 $1 !
    ${EndIf}
    ${If} $4 == '' ; The end?
      StrCpy $1 0
      StrCpy $4 ','
    ${EndIf}
    ${If} $4 == ','
    ${AndIf} $1 = 0
      StrCpy $4 $0 $3
      StrCpy $1 $4 "" -1
      ${IfThen} $1 == '"' ${|} StrCpy $4 $4 -1 ${|}
  killspace:
      IntOp $3 $3 + 1
      StrCpy $0 $0 "" $3
      StrCpy $1 $0 1
      StrCpy $3 0
      StrCmp $1 ',' killspace
      Push $0 ; Remaining
      Exch 4
      Pop $0
      ${If} $4 == ""
        Pop $4
        Pop $3
        Pop $1
        Return
      ${EndIf}
      Exch $4
      Exch 2
      Pop $1
      Pop $3
      Return
    ${EndIf}
    IntOp $3 $3 + 1
    Goto loop
  FunctionEnd
!macroend

!insertmacro INST_UNINST_SWITCH ""
!insertmacro INST_UNINST_SWITCH "un."


Function OnDirectoryPageLeave
  ;check if there are no files into $INSTDIR (recursively)
  StrCpy $9 "$INSTDIR"
  Call instDirEmpty
  StrCmp $9 "not empty" abort skip_abort
abort:
  ${LogText} "ERROR: installation dir is not empty: $INSTDIR"
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(choose_empty_folder)"
  Abort
skip_abort:
FunctionEnd


;check if there are no files into $INSTDIR recursively just except property files.
Function instDirEmpty
  Push $0
  Push $1
  Push $2
  ClearErrors
  FindFirst $1 $2 "$9\*.*"
  IfErrors done 0
next_element:
  ;is the element a folder?
  StrCmp $2 "." get_next_element
  StrCmp $2 ".." get_next_element
  IfFileExists "$9\$2\*.*" 0 next_file
    Push $9
    StrCpy "$9" "$9\$2"
    Call instDirEmpty
    StrCmp $9 "not empty" done 0
    Pop $9
    Goto get_next_element
next_file:
  ;is it the file property?
  ${If} $2 != "idea.properties"
    ${AndIf} $2 != "${PRODUCT_EXE_FILE}.vmoptions"
      StrCpy $9 "not empty"
      Goto done
  ${EndIf}
get_next_element:
  FindNext $1 $2
  IfErrors 0 next_element
done:
  ClearErrors
  FindClose $1
  Pop $2
  Pop $1
  Pop $0
FunctionEnd


Function getInstallationOptionsPositions
  !insertmacro INSTALLOPTIONS_READ $launcherShortcut "Desktop.ini" "Settings" "DesktopShortcut"
  !insertmacro INSTALLOPTIONS_READ $addToPath "Desktop.ini" "Settings" "AddToPath"
  !insertmacro INSTALLOPTIONS_READ $updateContextMenu "Desktop.ini" "Settings" "UpdateContextMenu"
FunctionEnd


Function ConfirmDesktopShortcut
  !insertmacro MUI_HEADER_TEXT "$(installation_options)" "$(installation_options_prompt)"

  Call getInstallationOptionsPositions

  IntOp $0 $launcherShortcut - 1
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $0" "Text" "$(create_desktop_shortcut)"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $launcherShortcut" "Text" "${MUI_PRODUCT}"
  IntOp $0 $addToPath - 1
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $0" "Text" "$(update_path_var_group)"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $addToPath" "Text" "$(update_path_var_label)"
  IntOp $0 $updateContextMenu - 1
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $0" "Text" "$(update_context_menu_group)"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $updateContextMenu" "Text" "$(update_context_menu_label)"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field ${INSTALL_OPTION_ELEMENTS}" "Text" "$(create_associations_group)"

  Call customPreInstallActions

  StrCmp "${ASSOCIATION}" "NoAssociation" skip_association
  StrCpy $R0 ${INSTALL_OPTION_ELEMENTS}
  ; start position for association checkboxes
  StrCpy $R1 0
  ; space between checkboxes
  StrCpy $R3 5
  ; space for one symbol
  StrCpy $R5 4
  push "${ASSOCIATION}"
loop:
  ; get an association from list of associations
  call SplitStr
  Pop $0
  StrCmp $0 "" done
  ; get length of an association text
  StrLen $R4 $0
  IntOp $R4 $R4 * $R5
  IntOp $R4 $R4 + 20
  ; increase field number
  IntOp $R0 $R0 + 1
  StrCmp $R1 0 first_association 0
  ; calculate  start position for next checkbox of an association using end of previous one.
  IntOp $R1 $R1 + $R3
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $R0" "Left" "$R1"
  Goto calculate_shift
first_association:
  !insertmacro INSTALLOPTIONS_READ $R2 "Desktop.ini" "Field $R0" "Left"
  StrCpy $R1 $R2
calculate_shift:
  IntOp $R1 $R1 + $R4
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $R0" "Right" "$R1"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $R0" "Text" "$0"
  goto loop
skip_association:
  IntOp $R0 ${INSTALL_OPTION_ELEMENTS} - 1
done:
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Settings" "NumFields" "$R0"
  !insertmacro INSTALLOPTIONS_DISPLAY "Desktop.ini"
FunctionEnd


;------------------------------------------------------------------------------
; configuration
;------------------------------------------------------------------------------

BrandingText " "

!define MUI_BRANDINGTEXT " "
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME

Page custom uninstallOldVersionDialog

!define MUI_PAGE_CUSTOMFUNCTION_LEAVE OnDirectoryPageLeave
!define MUI_PAGE_HEADER_TEXT "$(choose_install_location)"
!insertmacro MUI_PAGE_DIRECTORY

Page custom ConfirmDesktopShortcut

!define MUI_PAGE_HEADER_TEXT "$(choose_start_menu_folder)"
!define MUI_STARTMENUPAGE_DEFAULTFOLDER "JetBrains"
!insertmacro MUI_PAGE_STARTMENU Application $startMenuFolder

!define MUI_PAGE_HEADER_TEXT "$(installing_product)"
!insertmacro MUI_PAGE_INSTFILES

!ifdef RUN_AFTER_FINISH
!define MUI_FINISHPAGE_RUN_CHECKED
!else
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!endif
!define MUI_FINISHPAGE_REBOOTLATER_DEFAULT
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION PageFinishRun
!insertmacro MUI_PAGE_FINISH

!define MUI_UNINSTALLER
UninstPage custom un.ConfirmDeleteSettings
!insertmacro MUI_UNPAGE_INSTFILES

OutFile "${OUT_DIR}\${OUT_FILE}.exe"

InstallDir "$PROGRAMFILES64\${MANUFACTURER}\${INSTALL_DIR_AND_SHORTCUT_NAME}"

Function PageFinishRun
  IfSilent +2 +1
  !insertmacro UAC_AsUser_ExecShell "" "${PRODUCT_EXE_FILE}" "" "$INSTDIR\bin" ""
FunctionEnd

;------------------------------------------------------------------------------
; languages
;------------------------------------------------------------------------------
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "Japanese"
!insertmacro MUI_LANGUAGE "Korean"
!include "idea_en.nsi"
!include "idea_zh_CN.nsi"
!include "idea_ja.nsi"
!include "idea_ko.nsi"


Function .onInstSuccess
  SetErrorLevel 0
  ${LogText} "Installation has been finished successfully."
FunctionEnd


function silentInstallDirValidate
  ${If} $silentMode == "user"
    ${StrLoc} $R0 $INSTDIR "$PROGRAMFILES\${MANUFACTURER}" ">"
    ${If} $R0 == ""
      ${StrLoc} $R0 $INSTDIR "$PROGRAMFILES64\${MANUFACTURER}" ">"
      ${If} $R0 == ""
        ${LogText} "Silent installation dir: $INSTDIR"
        Return
      ${EndIf}
    ${EndIf}

    ${LogText} ""
    ${LogText} "  NOTE: Specified directory '$INSTDIR' requires administrative rights."
    ${LogText} "  It is corresponding to the 'admin' mode in the silent config file."
    ${LogText} "  But installation has been run in the 'user' mode. So the directory has been changed to the default: "
    StrCpy $INSTDIR "$LOCALAPPDATA\Programs\${PRODUCT_WITH_VER}"
    ${LogText} "  $INSTDIR "
    ${LogText} ""
  ${EndIf}
FunctionEnd


Function silentConfigReader
  ; read Desktop.ini
  ${LogText} ""
  ${LogText} "Silent installation, options"
  Call getInstallationOptionsPositions
  ${GetParameters} $R0
  ClearErrors

  ${GetOptions} $R0 /CONFIG= $R1
  IfErrors no_silent_config
  ${LogText} "  config file: $R1"

  ${ConfigRead} "$R1" "mode=" $R0
  IfErrors bad_silent_config
  ${LogText} "  mode: $R0"
  StrCpy $silentMode "user"
  IfErrors launcher
  StrCpy $silentMode $R0

launcher:
  ClearErrors
  ${ConfigRead} "$R1" "launcher64=" $R3
  IfErrors update_PATH
  ${LogText} "  shortcut for launcher64: $R3"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $launcherShortcut" "State" $R3

update_PATH:
  ClearErrors
  ${ConfigRead} "$R1" "updatePATH=" $R3
  IfErrors update_context_menu
  ${LogText} "  update PATH env var: $R3"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $addToPath" "Type" "checkbox"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $addToPath" "State" $R3

update_context_menu:
  ClearErrors
  ${ConfigRead} "$R1" "updateContextMenu=" $R3
  IfErrors associations
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $updateContextMenu" "Type" "checkbox"
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $updateContextMenu" "State" $R3

associations:
  ClearErrors
  StrCmp "${ASSOCIATION}" "NoAssociation" done
  !insertmacro INSTALLOPTIONS_READ $R0 "Desktop.ini" "Settings" "NumFields"
  push "${ASSOCIATION}"
loop:
  call SplitStr
  Pop $0
  StrCmp $0 "" update_settings
  ClearErrors
  ${ConfigRead} "$R1" "$0=" $R3
  IfErrors update_settings
  IntOp $R0 $R0 + 1
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $R0" "State" $R3
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Field $R0" "Text" "$0"
  ${LogText} "  association: $0, state: $R3"
  goto loop

update_settings:
  !insertmacro INSTALLOPTIONS_WRITE "Desktop.ini" "Settings" "NumFields" "$R0"
  goto done
no_silent_config:
  ${LogText} "  config file was not provided"
  ${LogText} "  defaulting to admin mode"
  StrCpy $silentMode "admin"
  goto done
bad_silent_config:
  Call IncorrectSilentInstallParameters
done:
FunctionEnd


Function IncorrectSilentInstallParameters
  !define msg1 "How to run installation in silent mode:$\n"
  !define msg2 "<installation> /S /CONFIG=<path to silent config with file name> /D=<install dir>$\n$\n"
  !define msg3 "Examples:$\n"
  !define msg4 "Installation.exe /S /CONFIG=d:\download\silent.config /D=d:\JetBrains\Product$\n"
  !define msg5 "Run installation in silent mode with logging:$\n"
  !define msg6 "Installation.exe /S /CONFIG=d:\download\silent.config /LOG=d:\JetBrains\install.log /D=d:\JetBrains\Product$\n"
  MessageBox MB_OK|MB_ICONSTOP "${msg1}${msg2}${msg3}${msg4}${msg5}${msg6}"
  ${LogText} "ERROR: silent installation: incorrect parameters."
  Abort
FunctionEnd


Function checkVersion
  StrCpy $2 ""
  StrCpy $1 "Software\${MANUFACTURER}\${PRODUCT_REG_VER}"
  Call OMReadRegStr
  IfFileExists $3\bin\${PRODUCT_EXE_FILE} check_version
  Goto done
check_version:
  StrCpy $9 $3
  StrCpy $2 "Build"
  Call OMReadRegStr
  StrCmp $3 "" done
  IntCmpU $3 ${VER_BUILD} ask_Install_Over done ask_Install_Over
ask_Install_Over:
  ${LogText} "  NOTE: ${PRODUCT_WITH_VER} is already installed:"
  ${LogText} "  $9"
  ${LogText} ""
  IfSilent continue 0
  MessageBox MB_YESNO|MB_ICONQUESTION "$(current_version_already_installed)" IDYES continue IDNO exit_installer
exit_installer:
  Abort
continue:
  StrCpy $0 "complete"
done:
FunctionEnd


Function searchCurrentVersion
  ${LogText} ""
  ${LogText} "Check if ${MUI_PRODUCT} ${VER_BUILD} already installed"
  ; search current version of IDEA
  StrCpy $0 "HKCU"
  Call checkVersion
  StrCmp $0 "complete" Done
  StrCpy $0 "HKLM"
  Call checkVersion
Done:
FunctionEnd


Function uninstallOldVersion
  ;uninstallation mode
  !insertmacro INSTALLOPTIONS_READ $9 "UninstallOldVersions.ini" "Field 2" "State"
  ${LogText} ""
  ${LogText} "Uninstall old installation: $3"

  ;do copy for unistall.exe
  CopyFiles "$3\bin\Uninstall.exe" "$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe"

  ${If} $9 == "1"
    ExecWait '"$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe" /S /NO_UNINSTALL_FEEDBACK=true _?=$3\bin'
  ${else}
    ExecWait '"$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe" /NO_UNINSTALL_FEEDBACK=true _?=$3\bin'
  ${EndIf}
  IfFileExists $3\bin\${PRODUCT_EXE_FILE} 0 uninstall
  goto complete
uninstall:
  ;previous installation has been removed
  ;customer has decided to keep properties?
  Delete "$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe"
complete:
FunctionEnd


Function checkProductVersion
;$8 - count of already added fields to the dialog
;$3 - an old version which will be checked if the one should be added too
  StrCpy $7 $control_fields
  StrCpy $6 ""
loop:
  IntOp $7 $7 + 1
  ${If} $8 >= $7
    !insertmacro INSTALLOPTIONS_READ $6 "UninstallOldVersions.ini" "Field $7" "Text"
    ${If} $6 == $3
      ;found the same value in list of installations
      StrCpy $6 "duplicated"
      Goto finish
    ${EndIf}
    Goto loop
  ${EndIf}
finish:
FunctionEnd


Function getUninstallOldVersionVars
  !insertmacro INSTALLOPTIONS_READ $max_fields "UninstallOldVersions.ini" "Settings" "NumFields"
  !insertmacro INSTALLOPTIONS_READ $control_fields "UninstallOldVersions.ini" "Settings" "ControlFields"
  !insertmacro INSTALLOPTIONS_READ $bottom_position "UninstallOldVersions.ini" "Settings" "BottomPosition"
  !insertmacro INSTALLOPTIONS_READ $max_length "UninstallOldVersions.ini" "Settings" "MaxLength"
  !insertmacro INSTALLOPTIONS_READ $line_width "UninstallOldVersions.ini" "Settings" "LineWidth"
  !insertmacro INSTALLOPTIONS_READ $extra_space "UninstallOldVersions.ini" "Settings" "ExtraSpace"
FunctionEnd


Function getPosition
; return:
;    0 if it is first checkbox which do not require special position
;    Bottom position of previous checkbox which equals for Top position of current one.
  IntOp $R8 $8 - 1
  !insertmacro INSTALLOPTIONS_READ $R7 "UninstallOldVersions.ini" "Field $R8" "Bottom"
  !insertmacro INSTALLOPTIONS_READ $7  "UninstallOldVersions.ini" "Field $8"  "Top"
  StrCmp $R8 $control_fields noCheckboxesFound 0
    Push $R7
    Goto done
noCheckboxesFound:
    Push $7
done:
FunctionEnd


Function getAdditionalSpaceForCheckbox
; $3 - a path to an old installation
; return
;   - 0 for 1-line checkbox
;   - a value for additional space for multi-line checkbox
  StrLen $9 $3
  ${If} $9 >= $max_length
    ; installation path is long
    Push $extra_space
    Goto done
  ${Else}
    Push 0
  ${EndIf}
done:
FunctionEnd


Function haveSpaceForTheCheckbox
  ; check if dialog has space for current checkbox
  !insertmacro INSTALLOPTIONS_READ $7 "UninstallOldVersions.ini" "Field $8" "Bottom"
  IntOp $7 $bottom_position - $7
  ${If} $7 >= 0
    Push 0
    Goto done
  ${Else}
    IntOp $8 $8 - 1
    Push 1
  ${EndIf}
done:
FunctionEnd


Function uninstallOldVersionDialog
  StrCpy $0 "HKLM"
  StrCpy $4 0
  StrCpy $8 $control_fields
  !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field 2" "State" "0"

get_installation_info:
  StrCpy $1 "Software\${MANUFACTURER}\${MUI_PRODUCT}"
  StrCpy $5 "\bin\${PRODUCT_EXE_FILE}"
  StrCpy $2 ""
  Call getInstallationPath
  StrCmp $3 "complete" next_registry_root
  ;check if the old installation could be uninstalled
  IfFileExists $3\bin\Uninstall.exe uninstall_dialog get_next_key
uninstall_dialog:
  Call checkProductVersion
  ${If} $6 != "duplicated"
    IntOp $8 $8 + 1
    Call getPosition
    Pop $7
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field $8" "Top" "$7"
    IntOp $R7 $7 + $line_width
    Call getAdditionalSpaceForCheckbox
    Pop $R9
    IntOp $R7 $R7 + $R9
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field $8" "Bottom" "$R7"
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field $8" "State" "0"
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field $8" "Text" "$3"
    Call haveSpaceForTheCheckbox
    Pop $9
    StrCmp $9 0 0 complete
  ${EndIf}
get_next_key:
  IntOp $4 $4 + 1 ;next record from registry
  goto get_installation_info

next_registry_root:
  ${If} $0 == "HKLM"
    StrCpy $0 "HKCU"
    StrCpy $4 0
    Goto get_installation_info
  ${EndIf}

complete:
  !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Settings" "NumFields" "$8"
  ${If} $8 > $control_fields
    ;$2 used in prompt text
    StrCpy $2 "s"
    StrCpy $7 $control_fields
    IntOp $7 $7 + 1
    StrCmp $8 $7 0 +2
      StrCpy $2 ""
    !insertmacro MUI_HEADER_TEXT "$(uninstall_previous_installations_title)" ""
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field 1" "Text" "$(uninstall_previous_installations_prompt)"
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field 2" "Text" "$(uninstall_previous_installations_silent)"
    !insertmacro INSTALLOPTIONS_WRITE "UninstallOldVersions.ini" "Field 3" "Flags" "FOCUS"
    !insertmacro INSTALLOPTIONS_DISPLAY_RETURN "UninstallOldVersions.ini"
    Pop $9
    ${If} $9 == "success"
loop:
      ;uninstall chosen installation(s)
      !insertmacro INSTALLOPTIONS_READ $0 "UninstallOldVersions.ini" "Field $8" "State"
      !insertmacro INSTALLOPTIONS_READ $3 "UninstallOldVersions.ini" "Field $8" "Text"
      ${If} $0 == "1"
        Call uninstallOldVersion
      ${EndIf}
      IntOp $8 $8 - 1
      StrCmp $8 $control_fields finish loop
    ${EndIf}
  ${EndIf}
finish:
FunctionEnd


Function getInstallationPath
  Push $1
  Push $2
  Push $5
loop:
  Call OMEnumRegKey
  StrCmp $3 "" 0 getPath
  StrCpy $3 "complete"
  goto done
getPath:
  Push $1
  StrCpy $1 "$1\$3"
  Call OMReadRegStr
  Pop $1
  IfFileExists $3$5 done 0
  IntOp $4 $4 + 1
  goto loop
done:
  Pop $5
  Pop $2
  Pop $1
FunctionEnd


Function GUIInit
  Push $0
  Push $1
  Push $2
  Push $3
  Push $4
  Push $5

; is the current version of IDEA installed?
  Call searchCurrentVersion

; search old versions of IDEA installed from the user and admin.
  ${LogText} "Search if old versions of ${MUI_PRODUCT} were installed"

  StrCpy $4 0
  StrCpy $0 "HKCU"
  StrCpy $1 "Software\${MANUFACTURER}\${MUI_PRODUCT}"
  StrCpy $5 "\bin\${PRODUCT_EXE_FILE}"
  StrCpy $2 ""
  Call getInstallationPath
  StrCmp $3 "complete" admin
  IfFileExists $3\bin\${PRODUCT_EXE_FILE} collect_versions admin
admin:
  StrCpy $4 0
  StrCpy $0 "HKLM"
  Call getInstallationPath

collect_versions:
  IntCmp ${SHOULD_SET_DEFAULT_INSTDIR} 0 end_enum_versions_hklm
; latest build number and registry key index
  StrCpy $3 "0"
  StrCpy $0 "0"

enum_versions_hkcu:
  EnumRegKey $1 "HKCU" "Software\${MANUFACTURER}\${MUI_PRODUCT}" $0
  StrCmp $1 "" end_enum_versions_hkcu
  IntCmp $1 $3 continue_enum_versions_hkcu continue_enum_versions_hkcu
  StrCpy $3 $1
  ReadRegStr $INSTDIR "HKCU" "Software\${MANUFACTURER}\${MUI_PRODUCT}\$3" ""

continue_enum_versions_hkcu:
  IntOp $0 $0 + 1
  Goto enum_versions_hkcu

end_enum_versions_hkcu:
  StrCpy $0 "0"        # registry key index

enum_versions_hklm:
  EnumRegKey $1 "HKLM" "Software\${MANUFACTURER}\${MUI_PRODUCT}" $0
  StrCmp $1 "" end_enum_versions_hklm
  IntCmp $1 $3 continue_enum_versions_hklm continue_enum_versions_hklm
  StrCpy $3 $1
  ReadRegStr $INSTDIR "HKLM" "Software\${MANUFACTURER}\${MUI_PRODUCT}\$3" ""

continue_enum_versions_hklm:
  IntOp $0 $0 + 1
  Goto enum_versions_hklm

end_enum_versions_hklm:
  StrCmp $INSTDIR "" 0 skip_default_instdir
  StrCpy $INSTDIR "$PROGRAMFILES64\${MANUFACTURER}\${INSTALL_DIR_AND_SHORTCUT_NAME}"

skip_default_instdir:
  Pop $5
  Pop $4
  Pop $3
  Pop $2
  Pop $1
  Pop $0
  !insertmacro INSTALLOPTIONS_EXTRACT "Desktop.ini"
FunctionEnd


Function ProductRegistration
  ${LogText} ""
  ${LogText} "Do registration ${MUI_PRODUCT} ${VER_BUILD}"
  StrCmp "${PRODUCT_WITH_VER}" "${MUI_PRODUCT} ${VER_BUILD}" eapInfo releaseInfo
eapInfo:
  StrCpy $3 "${PRODUCT_WITH_VER}(EAP)"
  goto createRegistration
releaseInfo:
  StrCpy $3 "${PRODUCT_WITH_VER}"
createRegistration:
  StrCpy $0 "HKCR"
  StrCpy $1 "Applications\${PRODUCT_EXE_FILE}\shell\open"
  StrCpy $2 "FriendlyAppName"
  call OMWriteRegStr
  StrCpy $1 "Applications\${PRODUCT_EXE_FILE}\shell\open\command"
  StrCpy $2 ""
  StrCpy $3 '"$productLauncher" "%1"'
  call OMWriteRegStr
FunctionEnd


Function UpdateContextMenu
  ${LogText} ""
  ${LogText} "Update Context Menu - Open with PRODUCT action for folders"

; add "Open with PRODUCT" action for folders to Windows context menu
  StrCpy $0 "SHCTX"
  StrCpy $1 "Software\Classes\Directory\shell\${MUI_PRODUCT}"
  StrCpy $2 ""
  StrCpy $3 "Open Folder as ${MUI_PRODUCT} Project"
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\Directory\shell\${MUI_PRODUCT}"
  StrCpy $2 "Icon"
  StrCpy $3 "$productLauncher"
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\Directory\shell\${MUI_PRODUCT}\command"
  StrCpy $2 ""
  StrCpy $3 '"$productLauncher" "%1"'
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\Directory\Background\shell\${MUI_PRODUCT}"
  StrCpy $2 ""
  StrCpy $3 "Open Folder as ${MUI_PRODUCT} Project"
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\Directory\Background\shell\${MUI_PRODUCT}"
  StrCpy $2 "Icon"
  StrCpy $3 "$productLauncher"
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\Directory\Background\shell\${MUI_PRODUCT}\command"
  StrCpy $2 ""
  StrCpy $3 '"$productLauncher" "%V"'
  call OMWriteRegStr
FunctionEnd


Function ProductAssociation
  ${LogText} ""
  ${LogText} "Do associations ${MUI_PRODUCT} ${VER_BUILD}"
  push $0
  push $1
  push $2
  push $3
  StrCpy $2 ""
  StrCmp $baseRegKey "HKLM" admin user
admin:
  StrCpy $0 HKCR
  StrCpy $R5 ${PRODUCT_PATHS_SELECTOR}
  goto back_up
user:
  StrCpy $0 HKCU
  StrCpy $R4 "Software\Classes\$R4"
  StrCpy $R5 "Software\Classes\${PRODUCT_PATHS_SELECTOR}"
back_up:
 ; back up old value of an association
  StrCpy $1 $R4
call OMReadRegStr
  StrCmp $3 "" skip_backup
  StrCmp $3 ${PRODUCT_PATHS_SELECTOR} skip_backup
  StrCpy $2 "backup_val"
  Call OMWriteRegStr
skip_backup:
  StrCpy $2 ""
  StrCpy $3 ${PRODUCT_PATHS_SELECTOR}
  Call OMWriteRegStr
  StrCpy $1 $R5
  StrCpy $2 ""
  Call OMReadRegStr
  StrCmp $3 "" 0 command_exists
  StrCpy $2 ""
  StrCpy $3 "${PRODUCT_FULL_NAME}"
  Call OMWriteRegStr
  StrCpy $1 "$R5\shell"
  StrCpy $2 ""
  StrCpy $3 "open"
  Call OMWriteRegStr
  StrCpy $1 "$R5\DefaultIcon"
  StrCpy $2 ""
  StrCpy $3 "$productLauncher,0"
  Call OMWriteRegStr
command_exists:
  StrCpy $1 "$R5\DefaultIcon"
  StrCpy $2 ""
  StrCpy $3 "$productLauncher,0"
  Call OMWriteRegStr
  StrCpy $1 "$R5\shell\open\command"
  StrCpy $2 ""
  StrCpy $3 '"$productLauncher" "%1"'
  Call OMWriteRegStr

  ; add "Edit with PRODUCT" action for files to Windows context menu
  ${LogText} ""
  ${LogText} "Update Context Menu - Edit with PRODUCT"

  StrCpy $0 "SHCTX"
  StrCpy $1 "Software\Classes\*\shell\Open with ${MUI_PRODUCT}"
  StrCpy $2 "Icon"
  StrCpy $3 "$productLauncher"
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\*\shell\Open with ${MUI_PRODUCT}\command"
  StrCpy $2 ""
  StrCpy $3 '"$productLauncher" "%1"'
  call OMWriteRegStr

  StrCpy $1 "Software\Classes\*\shell\Open with ${MUI_PRODUCT}"
  StrCpy $2 ""
  StrCpy $3 "Edit with ${MUI_PRODUCT}"
  call OMWriteRegStr

  pop $3
  pop $2
  pop $1
  pop $0
FunctionEnd


Function updatePathEnvVar
  Var /GLOBAL pathEnvVar

  ClearErrors
  ReadRegStr $pathEnvVar HKCU "Environment" "Path"
  ${If} ${Errors}
    ${LogText} "  ERROR: cannot read the 'Path' env var"
    Return
  ${EndIf}

  ${LogText} "  writing product env var '${MUI_PRODUCT}' = '$INSTDIR\bin'"
  WriteRegStr HKCU "Environment" "${MUI_PRODUCT}" "$INSTDIR\bin"
  ${If} ${Errors}
    ${LogText} "  ERROR: cannot write a product env var"
    Return
  ${EndIf}

  ${StrStr} $R0 $pathEnvVar "%${MUI_PRODUCT}%"
  ${If} $R0 != ""
    ${LogText} "  '${MUI_PRODUCT}' is already on the path"
    Return
  ${EndIf}

  ${If} $pathEnvVar != ""
    StrCpy $R0 $pathEnvVar 1 -1
    ${If} $R0 != ';'
      StrCpy $pathEnvVar "$pathEnvVar;"
    ${EndIf}
  ${EndIf}
  WriteRegExpandStr HKCU "Environment" "Path" "$pathEnvVar%${MUI_PRODUCT}%"
  ${If} ${Errors}
    ${LogText} "  ERROR: cannot write the 'Path' env var"
    Return
  ${EndIf}

  SetRebootFlag true
FunctionEnd


;------------------------------------------------------------------------------
; Installer sections
;------------------------------------------------------------------------------
Section "IDEA Files" CopyIdeaFiles
  CreateDirectory $INSTDIR

  Call customInstallActions

  StrCpy $productLauncher "$INSTDIR\bin\${PRODUCT_EXE_FILE}"
  ${LogText} "Default launcher: $productLauncher"
  DetailPrint "Default launcher: $productLauncher"

  !insertmacro INSTALLOPTIONS_READ $R0 "Desktop.ini" "Field $addToPath" "State"
  ${If} $R0 == 1
    ${LogText} "Updating the 'Path' env var"
    CALL updatePathEnvVar
  ${EndIf}

  ${If} $updateContextMenu > 0
    !insertmacro INSTALLOPTIONS_READ $R0 "Desktop.ini" "Field $updateContextMenu" "State"
    ${If} $R0 == 1
      Call UpdateContextMenu
    ${EndIf}
  ${EndIf}

  !insertmacro INSTALLOPTIONS_READ $R1 "Desktop.ini" "Settings" "NumFields"
  IntCmp $R1 ${INSTALL_OPTION_ELEMENTS} do_association done do_association
do_association:
  StrCpy $R2 ${INSTALL_OPTION_ELEMENTS}
get_user_choice:
  !insertmacro INSTALLOPTIONS_READ $R3 "Desktop.ini" "Field $R2" "State"
  StrCmp $R3 1 "" next_association
  !insertmacro INSTALLOPTIONS_READ $R4 "Desktop.ini" "Field $R2" "Text"
  call ProductAssociation
next_association:
  IntOp $R2 $R2 + 1
  IntCmp $R1 $R2 get_user_choice done get_user_choice
done:
  StrCmp ${IPR} "false" skip_ipr

  ; back up old value of .ipr
  !define Index "Line${__LINE__}"
  ReadRegStr $1 HKCR ".ipr" ""
  StrCmp $1 "" "${Index}-NoBackup"
    StrCmp $1 "IntelliJIdeaProjectFile" "${Index}-NoBackup"
    WriteRegStr HKCR ".ipr" "backup_val" $1
"${Index}-NoBackup:"
  WriteRegStr HKCR ".ipr" "" "IntelliJIdeaProjectFile"
  ReadRegStr $0 HKCR "IntelliJIdeaProjectFile" ""
  StrCmp $0 "" 0 "${Index}-Skip"
	WriteRegStr HKCR "IntelliJIdeaProjectFile" "" "IntelliJ IDEA Project File"
	WriteRegStr HKCR "IntelliJIdeaProjectFile\shell" "" "open"
"${Index}-Skip:"
  WriteRegStr HKCR "IntelliJIdeaProjectFile\DefaultIcon" "" "$productLauncher,0"
  WriteRegStr HKCR "IntelliJIdeaProjectFile\shell\open\command" "" '"$productLauncher" "%1"'
!undef Index

skip_ipr:
  ; readonly section
  ${LogText} ""
  ${LogText} "Copy files to $INSTDIR"
  SectionIn RO

  ; main part
  !include "idea_win.nsh"

  ; registering the application for the "Open With" list
  Call ProductRegistration

  ; setting the working directory for subsequent `CreateShortCut` instructions
  SetOutPath "$INSTDIR"

  ; creating the desktop shortcut
  !insertmacro INSTALLOPTIONS_READ $R0 "Desktop.ini" "Field $launcherShortcut" "State"
  ${If} $R0 == 1
    ${LogText} "Creating shortcut: '$DESKTOP\${INSTALL_DIR_AND_SHORTCUT_NAME}.lnk' -> '$productLauncher'"
    CreateShortCut "$DESKTOP\${INSTALL_DIR_AND_SHORTCUT_NAME}.lnk" "$productLauncher" "" "" "" SW_SHOWNORMAL
  ${EndIf}

  ; creating the start menu shortcut and storing the start menu directory for the uninstaller
  ${If} $startMenuFolder != ""
    !insertmacro MUI_STARTMENU_WRITE_BEGIN Application
    CreateDirectory "$SMPROGRAMS\$startMenuFolder"
    CreateShortCut "$SMPROGRAMS\$startMenuFolder\${INSTALL_DIR_AND_SHORTCUT_NAME}.lnk" "$productLauncher" "" "" "" SW_SHOWNORMAL
    StrCpy $0 $baseRegKey
    StrCpy $1 "Software\${MANUFACTURER}\${PRODUCT_REG_VER}"
    StrCpy $2 "MenuFolder"
    StrCpy $3 "$startMenuFolder"
    Call OMWriteRegStr
    !insertmacro MUI_STARTMENU_WRITE_END
  ${Else}
    DetailPrint "Skipping start menu shortcut."
  ${EndIf}

  ; enabling Java assistive technologies if a screen reader is active (0x0046 = SPI_GETSCREENREADER)
  System::Call "User32::SystemParametersInfo(i 0x0046, i 0, *i .r1, i 0) i .r0"
  ${LogText} "SystemParametersInfo(SPI_GETSCREENREADER): $0, value=$1"
  ${If} $0 <> 0
  ${AndIf} $1 == 1
    ${If} ${FileExists} "$INSTDIR\jbr\bin\jabswitch.exe"
      ${LogText} "Executing '$\"$INSTDIR\jbr\bin\jabswitch.exe$\" /enable'"
      ExecDos::exec /DETAILED '"$INSTDIR\jbr\bin\jabswitch.exe" /enable' '' ''
      Pop $0
      ${LogText} "Exit code: $0"
    ${EndIf}
    ${If} ${FileExists} "$INSTDIR\jbr\bin\WindowsAccessBridge-64.dll"
    ${AndIfNot} ${FileExists} "$SYSDIR\WindowsAccessBridge-64.dll"
      ${LogText} "Copying '$INSTDIR\jbr\bin\WindowsAccessBridge-64.dll' into '$SYSDIR'"
      ${DisableX64FSRedirection}
      CopyFiles /SILENT "$INSTDIR\jbr\bin\WindowsAccessBridge-64.dll" "$SYSDIR"
      ${EnableX64FSRedirection}
    ${EndIf}
  ${EndIf}

  Call customPostInstallActions

  StrCpy $0 $baseRegKey
  StrCpy $1 "Software\${MANUFACTURER}\${PRODUCT_REG_VER}"
  StrCpy $2 ""
  StrCpy $3 "$INSTDIR"
  Call OMWriteRegStr
  StrCpy $2 "Build"
  StrCpy $3 ${VER_BUILD}
  Call OMWriteRegStr

  ; writing the uninstaller & creating the uninstall record
  WriteUninstaller "$INSTDIR\bin\Uninstall.exe"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "DisplayName" "${INSTALL_DIR_AND_SHORTCUT_NAME}"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "UninstallString" "$INSTDIR\bin\Uninstall.exe"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "InstallLocation" "$INSTDIR"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "DisplayIcon" "$productLauncher"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "DisplayVersion" "${VER_BUILD}"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "Publisher" "JetBrains s.r.o."
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "URLInfoAbout" "https://www.jetbrains.com/products"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "InstallType" "$baseRegKey"
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "NoModify" 1
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}" "NoRepair" 1

  ; reset icon cache
  ${LogText} "Reset icon cache"
  System::Call 'shell32.dll::SHChangeNotify(i, i, i, i) v (0x08000000, 0, 0, 0)'
SectionEnd


Function .onInit
  SetRegView 64
  Call createLog

  ${GetNativeMachineArchitecture} $R0
  ${IfNot} $R0 == ${INSTALLER_ARCH}
  ${OrIfNot} ${AtLeastBuild} 14393  ; Windows 10 1607 / Windows Server 2016
    ${LogText} "Architecture: expected=${INSTALLER_ARCH} actual=$R0"
    ReadEnvStr $R0 "TEAMCITY_VERSION"
    ${If} $R0 == ""
      MessageBox MB_OK "$(unsupported_win_version)"
      Abort
    ${Else}
      ${LogText} "  ... ignored on TeamCity"
    ${EndIf}
  ${EndIf}

  !insertmacro INSTALLOPTIONS_EXTRACT "UninstallOldVersions.ini"
  !insertmacro INSTALLOPTIONS_EXTRACT "Desktop.ini"
  Call getInstallationOptionsPositions
  Call getUninstallOldVersionVars
  IfSilent silent_mode uac_elevate

silent_mode:
  Call checkAvailableRequiredDiskSpace
  IntCmp ${CUSTOM_SILENT_CONFIG} 0 silent_config silent_config custom_silent_config

silent_config:
  Call silentConfigReader
  Goto validate_install_dir
custom_silent_config:
  Call customSilentConfigReader

validate_install_dir:
  Call searchCurrentVersion
  Call silentInstallDirValidate
  StrCpy $baseRegKey "HKCU"
  StrCmp $silentMode "admin" uac_elevate installdir_is_empty

uac_elevate:
  !insertmacro UAC_RunElevated
  StrCmp 1223 $0 uac_elevation_aborted ; UAC dialog aborted by user? - continue install under user
  StrCmp 0 $0 0 uac_err ; Error?
  StrCmp 1 $1 0 uac_success ;Are we the real deal or just the wrapper?
  Quit
uac_err:
  Abort
uac_elevation_aborted:
  ${LogText} ""
  ${LogText} "  NOTE: UAC elevation has been aborted. Installation dir will be changed."
  ${LogText} ""
  StrCpy $INSTDIR "$LOCALAPPDATA\Programs\${INSTALL_DIR_AND_SHORTCUT_NAME}"
  goto installdir_is_empty
uac_success:
  StrCmp 1 $3 uac_admin ;Admin?
  StrCmp 3 $1 0 uac_elevation_aborted ;Try again?
  goto uac_elevate
uac_admin:
  IfSilent uac_all_users set_install_dir_admin_mode
set_install_dir_admin_mode:
  StrCpy $INSTDIR "$PROGRAMFILES64\${MANUFACTURER}\${INSTALL_DIR_AND_SHORTCUT_NAME}"
uac_all_users:
  SetShellVarContext all
  StrCpy $baseRegKey "HKLM"
installdir_is_empty:
  IfSilent 0 done
; Check in silent mode if install folder is not empty.
  Call OnDirectoryPageLeave
done:
  ${LogText} "Installation dir: $INSTDIR"
  ${If} $Language == ${LANG_SIMPCHINESE}
    System::Call "kernel32::GetUserDefaultUILanguage() h .r10"
    ${If} $R0 != ${LANG_SIMPCHINESE}
      ${LogText} "Language override: $R0 != ${LANG_SIMPCHINESE}"
      StrCpy $Language ${LANG_ENGLISH}
    ${EndIf}
  ${EndIf}
  ;!insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd


Function checkAvailableRequiredDiskSpace
  SectionGetSize ${CopyIdeaFiles} $requiredDiskSpace
  ${LogText} "Space required: $requiredDiskSpace KB"
  Push $INSTDIR
  StrCpy $9 $INSTDIR 3
  Call FreeDiskSpace
  ${LogText} "Space available: $1 KB"

; required free space
  StrCpy $2 $requiredDiskSpace
; compare the space required and the space available
  System::Int64Op $1 > $2
  Pop $3

  IntCmp $3 1 done
    MessageBox MB_OK|MB_ICONSTOP "$(out_of_disk_space)"
    ${LogText} "ERROR: Not enough disk space!"
    Abort
done:
FunctionEnd


Function FreeDiskSpace
; $9 contains parent dir for installation
  System::Call 'Kernel32::GetDiskFreeSpaceEx(t "$9", *l.r1, *l.r2, *l.r3)i.r0'
  ${If} $0 <> 0
; convert byte values into KB
    System::Int64Op $1 / 1024
    Pop $1
  ${Else}
    ${LogText} "An error occurred during calculation disk space $0"
  ${EndIf}
FunctionEnd

;------------------------------------------------------------------------------
; custom uninstall functions
;------------------------------------------------------------------------------

Function un.getRegKey
  ReadRegStr $R2 HKCU "Software\${MANUFACTURER}\${PRODUCT_REG_VER}" ""
  StrCpy $R2 "$R2\bin"
  StrCmp $R2 $INSTDIR HKCU admin
HKCU:
  StrCpy $baseRegKey "HKCU"
  Goto Done
admin:
  ReadRegStr $R2 HKLM "Software\${MANUFACTURER}\${PRODUCT_REG_VER}" ""
  StrCpy $R2 "$R2\bin"
  StrCmp $R2 $INSTDIR HKLM cant_find_installation
HKLM:
  StrCpy $baseRegKey "HKLM"
  Goto Done

cant_find_installation:
; compare installdir with default user location
  ${UnStrStr} $R0 $INSTDIR "$LOCALAPPDATA\${MANUFACTURER}"
  StrCmp $R0 $INSTDIR HKCU 0

; compare installdir with default admin location
  ${UnStrStr} $R0 $INSTDIR $PROGRAMFILES64
  StrCmp $R0 $INSTDIR HKLM undefined_location

; installdir does not contain known default locations
undefined_location:
  Goto HKLM

Done:
FunctionEnd


Function un.onUninstSuccess
  SetErrorLevel 0
FunctionEnd


Function un.UninstallFeedback
; do not ask user about UNINSTALL FEEDBACK if uninstallation was run from another installation
  Push $R0
  Push $R1
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 /NO_UNINSTALL_FEEDBACK= $R1
  IfErrors done
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 6" "State" "0"
done:
  Pop $R1
  Pop $R0
  ClearErrors
FunctionEnd


Function un.onInit
  SetRegView 64

  !insertmacro INSTALLOPTIONS_EXTRACT "DeleteSettings.ini"
  Call un.UninstallFeedback

; Uninstallation was run from installation dir?
  IfFileExists "$INSTDIR\fsnotifier.exe" 0 end_of_uninstall
  IfFileExists "$INSTDIR\${PRODUCT_EXE_FILE}" 0 end_of_uninstall

  Call un.getRegKey
  StrCmp $baseRegKey "HKLM" uninstall_location UAC_Done

uninstall_location:
  ;check if the uninstallation is running from the product location
  IfFileExists $LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe UAC_Elevate required_admin_perm

required_admin_perm:
  ;the user has admin rights?
  UserInfo::GetAccountType
  Pop $R2
  StrCmp $R2 "Admin" UAC_Admin copy_uninstall

copy_uninstall:
  ;do copy for unistall.exe
  CopyFiles "$OUTDIR\Uninstall.exe" "$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe"
  IfSilent uninstall_silent_mode uninstall_gui_mode

uninstall_silent_mode:
  ExecWait '"$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe" /S _?=$INSTDIR'
  Goto delete_uninstaller_itself
uninstall_gui_mode:
  ExecWait '"$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe" _?=$INSTDIR'

delete_uninstaller_itself:
  Delete "$LOCALAPPDATA\${PRODUCT_PATHS_SELECTOR}_${VER_BUILD}_Uninstall.exe"
  RMDir "$INSTDIR\bin"
  RMDir "$INSTDIR"
  Quit

UAC_Elevate:
  !insertmacro UAC_RunElevated
  StrCmp 1223 $0 UAC_ElevationAborted ; UAC dialog aborted by user? - continue install under user
  StrCmp 0 $0 0 UAC_Err ; Error?
  StrCmp 1 $1 0 UAC_Success ;Are we the real deal or just the wrapper?
  Quit
UAC_ElevationAborted:
UAC_Err:
  Abort
UAC_Success:
  StrCmp 1 $3 UAC_Admin ;Admin?
  StrCmp 3 $1 0 UAC_ElevationAborted ;Try again?
  goto UAC_Elevate
UAC_Admin:
  SetShellVarContext all
  StrCpy $baseRegKey "HKLM"
  Goto UAC_Done
end_of_uninstall:
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(uninstaller_relocated)"
  Abort
UAC_Done:
  ${If} $Language == ${LANG_SIMPCHINESE}
    System::Call "kernel32::GetUserDefaultUILanguage() h .r10"
    ${If} $R0 != ${LANG_SIMPCHINESE}
      StrCpy $Language ${LANG_ENGLISH}
    ${EndIf}
  ${EndIf}
  ;!insertmacro MUI_UNGETLANGUAGE
FunctionEnd


Function un.RestoreBackupRegValue
  ;replace Default str with the backup value (if there is the one) and then delete backup
  ; $1 - key (for example ".java")
  ; $2 - name (for example "backup_val")
  Push $0
  Push $3

  StrCmp $baseRegKey "HKLM" admin user
admin:
  StrCpy $0 HKCR
  goto read_backup_value
user:
  StrCpy $0 HKCU
  StrCpy $1 "Software\Classes\$1"

read_backup_value:
  call un.OMReadRegStr
  StrCmp $3 "" no_backup restore_backup

no_backup:
  ;clean default value if it contains current product info
  StrCpy $2 ""
  call un.OMReadRegStr
  StrCmp $4 $3 0 done
  call un.OMDeleteRegValue
  goto done

restore_backup:
  StrCmp $3 $4 remove_backup 0
  push $2
  StrCpy $2 ""
  call un.OMWriteRegStr
  pop $2
remove_backup:
  call un.OMDeleteRegValue

done:
  Pop $3
  Pop $0
FunctionEnd


Function un.PSEnum
  ${If} $2 == "$INSTDIR\bin\${PRODUCT_EXE_FILE}"
  ${OrIf} $2 == "$INSTDIR\jbr\bin\java.exe"
    StrCpy $R1 "[$0] $2"
    DetailPrint "$R1"
    StrCpy $0 ""
  ${EndIf}
FunctionEnd

Function un.checkIfIDEIsRunning
  GetFunctionAddress $R0 un.PSEnum
check_processes:
  DetailPrint "Enumerating processes"
  StrCpy $R1 ""
  PS::Enum $R0
  ${If} $R1 == ""
    Return
  ${EndIf}
  MessageBox MB_OKCANCEL|MB_ICONQUESTION|MB_TOPMOST "$(application_running)" IDOK check_processes
  Abort
FunctionEnd


Function un.deleteDirectoryWithParent
  RMDir /R "$0"
  RMDir "$0\.."  ; delete a parent directory if empty
FunctionEnd


Function un.deleteShortcutIfRight
  ${IfNot} ${FileExists} "$0"
    DetailPrint "The $1 shortcut '$0' does does not exist."
    Return
  ${EndIf}

  ClearErrors
  ShellLink::GetShortCutTarget "$0"
  Pop $R1
  ${IfNot} ${Errors}
  ${AndIf} $R1 == "$INSTDIR\bin\${PRODUCT_EXE_FILE}"
    DetailPrint "Deleting the $1 shortcut: $0"
    Delete "$0"
    ${If} $1 == "start menu"
      RMDir "$0\.."  ; delete the parent group if empty
    ${EndIf}
  ${Else}
    DetailPrint "The link '$0' does does not point to a valid launcher."
  ${EndIf}
FunctionEnd


;------------------------------------------------------------------------------
; custom uninstall pages
;------------------------------------------------------------------------------

Function un.ConfirmDeleteSettings
  !insertmacro MUI_HEADER_TEXT "$(uninstall_options)" ""

  ${GetParent} $INSTDIR $R1
  ${UnStrRep} $R1 $R1 '\' '\\'
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 1" "Text" "$(prompt_delete_settings)"
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 2" "Text" $R1
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 3" "Text" "$(text_delete_settings)"
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 4" "Text" "$(confirm_delete_caches)"
  !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 5" "Text" "$(confirm_delete_settings)"

  ${UnStrStr} $R0 "${MUI_PRODUCT}" "JetBrains Rider"
  ${If} $R0 == "${MUI_PRODUCT}"
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 7" "Text" "$(confirm_delete_rider_build_tools)"
  ${Else}
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 7" "Type" "Label"
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 7" "Text" ""
  ${EndIf}

  ${If} "${UNINSTALL_WEB_PAGE}" != ""
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 6" "Text" "$(share_uninstall_feedback)"
  ${Else}
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 6" "Type" "Label"
    !insertmacro INSTALLOPTIONS_WRITE "DeleteSettings.ini" "Field 6" "Text" ""
  ${EndIf}

  !insertmacro INSTALLOPTIONS_DISPLAY "DeleteSettings.ini"
FunctionEnd


Section "Uninstall"
  DetailPrint "baseRegKey: $baseRegKey"

  ; the uninstaller is in the "...\bin" subdirectory; correcting
  ${GetParent} "$INSTDIR" $INSTDIR
  DetailPrint "Uninstalling from: $INSTDIR"

  Call un.checkIfIDEIsRunning

  Call un.customUninstallActions

  ; deleting the start menu shortcut
  StrCpy $0 $baseRegKey
  StrCpy $1 "Software\${MANUFACTURER}\${PRODUCT_REG_VER}"
  StrCpy $2 "MenuFolder"
  Call un.OMReadRegStr
  ${If} $3 != ""
    StrCpy $0 "$SMPROGRAMS\$3\${INSTALL_DIR_AND_SHORTCUT_NAME}.lnk"
    StrCpy $1 "start menu"
    Call un.deleteShortcutIfRight
  ${EndIf}

  ; deleting the desktop shortcut
  StrCpy $0 "$DESKTOP\${INSTALL_DIR_AND_SHORTCUT_NAME}.lnk"
  StrCpy $1 "desktop"
  Call un.deleteShortcutIfRight

  ; deleting the 'Path' record
  ReadRegStr $R0 HKCU "Environment" "${MUI_PRODUCT}"
  ${If} $R0 == "$INSTDIR\bin"
    ReadRegStr $R1 HKCU "Environment" "Path"
    ${UnStrRep} $R2 $R1 ";%${MUI_PRODUCT}%" ""
    ${If} $R2 != $R1
    ${AndIf} $R2 != ""
      DetailPrint "Updating the 'Path' environment variable."
      WriteRegExpandStr HKCU "Environment" "Path" "$R2"
      SetRebootFlag true
    ${EndIf}
    DetailPrint "Deleting the '${MUI_PRODUCT}' environment variable."
    DeleteRegValue HKCU "Environment" "${MUI_PRODUCT}"
  ${EndIf}

  ; setting the context for `$APPDATA` and `$LOCALAPPDATA`
  ${If} $baseRegKey == "HKLM"
    SetShellVarContext current
  ${EndIf}

  ; deleting caches
  !insertmacro INSTALLOPTIONS_READ $R2 "DeleteSettings.ini" "Field 4" "State"
  ${If} $R2 == 1
    StrCpy $0 "$LOCALAPPDATA\${MANUFACTURER}\${PRODUCT_PATHS_SELECTOR}"
    DetailPrint "Deleting caches: $0"
    Call un.deleteDirectoryWithParent
  ${Else}
    DetailPrint "Keeping caches"
  ${EndIf}

  ; deleting settings
  !insertmacro INSTALLOPTIONS_READ $R2 "DeleteSettings.ini" "Field 5" "State"
  ${If} $R2 == 1
    StrCpy $0 "$APPDATA\${MANUFACTURER}\${PRODUCT_PATHS_SELECTOR}"
    DetailPrint "Deleting settings: $0"
    Call un.deleteDirectoryWithParent
  ${Else}
    DetailPrint "Keeping settings"
  ${EndIf}

  ; restoring the context
  ${If} $baseRegKey == "HKLM"
    SetShellVarContext all
  ${EndIf}

  ; deleting the uninstaller itself and other cruft
  Delete "$INSTDIR\bin\Uninstall.exe"
  Delete "$INSTDIR\jbr\bin\server\classes.jsa"

  ; main part
  !include "un_idea_win.nsh"
  RMDir "$INSTDIR\bin"
  RMDir "$INSTDIR"

  ; removing the directory context menu action
  StrCpy $0 "SHCTX"
  StrCpy $1 "Software\Classes\*\shell\Open with ${MUI_PRODUCT}"
  Call un.OMDeleteRegKey
  StrCpy $1 "Software\Classes\Directory\shell\${MUI_PRODUCT}"
  Call un.OMDeleteRegKey
  StrCpy $1 "Software\Classes\Directory\Background\shell\${MUI_PRODUCT}"
  Call un.OMDeleteRegKey

  ; restoring file associations
  StrCpy $5 "Software\${MANUFACTURER}"
  StrCmp "${ASSOCIATION}" "NoAssociation" finish_uninstall
  push "${ASSOCIATION}"
loop:
  StrCpy $2 "backup_val"
  StrCpy $4 "${PRODUCT_PATHS_SELECTOR}"
  call un.SplitStr
  Pop $0
  StrCmp $0 "" finish_uninstall

  ;restore backup association(s)
  StrCpy $1 $0
  Call un.RestoreBackupRegValue
  goto loop

finish_uninstall:
  StrCpy $0 $baseRegKey
  StrCpy $1 "$5\${PRODUCT_REG_VER}"
  StrCpy $4 0

getValue:
  Call un.OMEnumRegValue
  IfErrors finish delValue
delValue:
  StrCpy $2 $3
  Call un.OMDeleteRegValue
  IfErrors 0 +2
  IntOp $4 $4 + 1
  goto getValue

finish:
  StrCpy $1 "$5\${PRODUCT_REG_VER}"
  Call un.OMDeleteRegKeyIfEmpty
  StrCpy $1 "$5"
  Call un.OMDeleteRegKeyIfEmpty

  StrCpy $0 "HKCR"
  StrCpy $1 "Applications\${PRODUCT_EXE_FILE}"
  Call un.OMDeleteRegKey

  StrCpy $0 $baseRegKey
  StrCmp $baseRegKey "HKLM" admin user
admin:
  StrCpy $1 "${PRODUCT_PATHS_SELECTOR}"
  goto delete_association
user:
  StrCpy $1 "Software\Classes\${PRODUCT_PATHS_SELECTOR}"
delete_association:
  ; remove product information which was used for association(s)
  Call un.OMDeleteRegKey

  ; dropping the .ipr association
  StrCpy $0 "HKCR"
  StrCpy $1 "IntelliJIdeaProjectFile\DefaultIcon"
  StrCpy $2 ""
  Call un.OMReadRegStr
  ${If} $3 == "$INSTDIR\bin\${PRODUCT_EXE_FILE},0"
    StrCpy $1 "IntelliJIdeaProjectFile"
    Call un.OMDeleteRegKey
  ${EndIf}

  ; deleting the uninstall record
  StrCpy $0 $baseRegKey
  StrCpy $1 "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_WITH_VER}"
  Call un.OMDeleteRegKey

  ; opening the uninstall feedback page
  ${IfNot} ${Silent}
  ${AndIfNot} "${UNINSTALL_WEB_PAGE}" == ""
    !insertmacro INSTALLOPTIONS_READ $R2 "DeleteSettings.ini" "Field 6" "State"
    ${If} $R2 == 1
      ExecShell "" "${UNINSTALL_WEB_PAGE}"
    ${EndIf}
  ${EndIf}
SectionEnd
