# Licensed under the MIT License.
# 
# OrchestratorCICD.ps1 appsettings.json crossTrainedLUDirectory destGeneratedFolder destModelFolder
# 
# For example:
# .\OrchestratorCICD.ps1 C:\Users\daveta\Downloads\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\settings\appsettings.json C:\Users\daveta\Downloads\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\generated\interruption C:\Users\daveta\Downloads\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\generated C:\Users\daveta\Downloads\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\CoreAsistantWithOrchestrator\generated\models
#
# Used in conjunction with CICD, performs the following:
#  - Downloads base model(s) - English, Multilingual depending on configuration
#    Creates a "english" and "multilingual" directory.
#  - Builds Orchestrator language models (english and multilingual) snapshot files
#  - Creates configuration file used by runtime (orchestrator.settings.json)
# 

Param(
	[string] $sourceDirectory,
	[string] $crossTrainedLUDirectory,
	[string] $appSettingsFile,
	[string] $destGeneratedFolder,
	[string] $destModelFolder
)

# Import script with common functions
. ($PSScriptRoot + "/LUUtils.ps1")
#$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
#Import-Module -Name "$scriptDir/LUUtils.ps1"

if ($PSBoundParameters.Keys.Count -lt 5) {
    Write-Host "Dowload models and trains orchestrator" 
    Write-Host 'Usage: OrchestratorCICD.ps1 appsettings.json crossTrainedLUDirectory destGeneratedFolder destModelFolder'
    Write-Host 'Parameters: '
    Write-Host ' appsettings.json - Bot appsettings.json file.'
    Write-Host ' crossTrainedLUDirectory - Directory containing .lu/.qna files to process.'
    Write-Host ' destGeneratedFolder - Directory for processed .lu files'
    Write-Host " destModelFolder - Directory that contains intent models (creates 'english' and 'multilingual' subfolders)."
    exit
}

Write-Output " appsettings.json: $appSettingsFile"
Write-Output " crossTrainedLUDirectory: $crossTrainedLUDirectory"
Write-Output " destGeneratedFolder: $destGeneratedFolder"
Write-Output " destModelFolder: $destModelFolder"

Write-Host "Orchestrator models"
$models = Get-LUModels -recognizerType "Microsoft.OrchestratorRecognizer" -crossTrainedLUDirectory $crossTrainedLUDirectory -sourceDirectory $sourceDirectory
foreach($model in $models)
{
    Write-Host $model
}

#Write-Host "LUIS models"
#$models = Get-LUModels -recognizerType "Microsoft.LuisRecognizer" -crossTrainedLUDirectory $crossTrainedLUDirectory -sourceDirectory $sourceDirectory
#foreach($model in Get-LUModels "Microsoft.LuisRecognizer" $crossTrainedLUDirectory $sourceDirectory)
#{
#    Write-Host $model
#}

if ($models.Count -eq 0)
{
    Write-Host "No orchestrator models found."
    exit 0        
}

exit 0
$appSettings = Get-Content -Path $appSettingsFile | ConvertFrom-Json

# Determine which models we need to download and train.
$downloadEnglish = $false
$downloadMultiLingual = $false
Write-Output ' Loading json settings'
foreach ($language in $appSettings.languages) {
    if ($language.StartsWith('en')) {
        $downloadEnglish = $true
        Write-Output ' Found English.'
    }
    else {
        $downloadMultiLingual = $true
        Write-Output ' Found multilingual.'
    }
}

# Composer config output file json.
$COMPOSERCONFIG = "{
    orchestrator:{
        models:{},
        snapshots:{}
    }
}" | ConvertFrom-Json



if ($downloadEnglish) {
    # Create folder for all en-us .lu files
    if ((Test-Path -Path "$crossTrainedLUDirectory/english") -eq $false) {
        Write-Output "Creating $crossTrainedLUDirectory/english folder.."
        New-Item -Path "$crossTrainedLUDirectory" -Name "english" -ItemType "directory" -Force
        Write-Output "Created English input folder $crossTrainedLUDirectory/english"
    }

    # Enumerate all the en-us lu files.
    $LUFILES = Get-ChildItem -Path "$crossTrainedLUDirectory" -Include *en-us*.lu -Name
    foreach ( $file in $LUFILES) {
        Write-Output "Copying file $file to $crossTrainedLUDirectory/english ..."
        Copy-Item -Path "$crossTrainedLUDirectory/$file" -Destination "$crossTrainedLUDirectory/english"
    }

    # Create folder for English intent base model
    if ((Test-Path -Path "$destModelFolder/english") -eq $false) {
        Write-Output "Creating $destModelFolder/english folder.."
        New-Item -Path "$destModelFolder" -Name "english" -ItemType "directory" -force
        Write-Output "Created English model folder $destModelFolder/english"
    }

    bf orchestrator:basemodel:get -o "$destModelFolder/english"
    bf orchestrator:build --in "$crossTrainedLUDirectory/english" --out "$destGeneratedFolder" --model "$destModelFolder/english"
    $COMPOSERCONFIG.orchestrator.models | Add-Member -NotePropertyName en -NotePropertyValue "$destModelFolder/english"
}

if ($downloadMultiLingual) {
    # Create folder for all non-en-us .lu files
    if ((Test-Path -Path "$crossTrainedLUDirectory/multilingual") -eq $false) {
        Write-Output "Creating $crossTrainedLUDirectory/multilingual folder.."
        New-Item -Path "$crossTrainedLUDirectory" -Name "multilingual" -ItemType "directory" -Force
        Write-Output "Created English input folder $crossTrainedLUDirectory/multilingual"
    }
    # Enumerate all the non-en-us lu files.
    $LUFILES = Get-ChildItem -Path "$crossTrainedLUDirectory" -Include *.lu -Name -Exclude *en-us*
    foreach ( $file in $LUFILES) {
        Write-Output "Copying file $file to $crossTrainedLUDirectory/multilingual ..."
        Copy-Item -Path "$crossTrainedLUDirectory/$file" -Destination "$crossTrainedLUDirectory/multilingual"
    }
    # Create folder for Non-English intent base model
    if ((Test-Path -Path "$destModelFolder/multilingual") -eq $false) {
        Write-Output "Creating $destModelFolder/multilingual folder.."
        New-Item -Path "$destModelFolder" -Name "multilingual" -ItemType "directory" -force
        Write-Output "Created Multilingual model folder $destModelFolder/multilingual"
    }
    bf orchestrator:basemodel:get -o "$destModelFolder/multilingual" --versionId pretrained.20210205.microsoft.dte.00.06.unicoder_multilingual.onnx
    bf orchestrator:build --in "$crossTrainedLUDirectory/multilingual" --out "$destGeneratedFolder" --model "$destModelFolder/multilingual"
    $COMPOSERCONFIG.orchestrator.models | Add-Member -NotePropertyName multilang -NotePropertyValue "$destModelFolder/multilingual"
}

Write-Output "Writing output file $destGeneratedFolder/orchestrator.settings.json"
$BLUFILES = Get-ChildItem -Path "$destGeneratedFolder" -Include *.blu -Name
foreach ($file in $BLUFILES) {
    $key = $file -replace ".{4}$"
    $key = $key.Replace(".", "_")
    $COMPOSERCONFIG.orchestrator.snapshots | Add-Member -NotePropertyName "$key" -NotePropertyValue "$crossTrainedLUDirectory/$file"
}

$COMPOSERCONFIG | ConvertTo-Json | Out-File -FilePath "$destGeneratedFolder/orchestrator.settings.json"