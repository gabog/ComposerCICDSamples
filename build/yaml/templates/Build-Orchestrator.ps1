# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
# 
# OrchestratorCICD.ps1 appsettings.json crossTrainedLUDirectory generatedDirectory destModelFolder
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
	[string] $generatedDirectory,
	[string] $destModelFolder
)

# Import script with common functions
. ($PSScriptRoot + "/LUUtils.ps1")

if ($PSBoundParameters.Keys.Count -lt 5) {
    Write-Host "Dowload models and trains orchestrator" 
    Write-Host 'Usage: OrchestratorCICD.ps1 appsettings.json crossTrainedLUDirectory generatedDirectory destModelFolder'
    Write-Host 'Parameters: '
    Write-Host ' appsettings.json - Bot appsettings.json file.'
    Write-Host ' crossTrainedLUDirectory - Directory containing .lu/.qna files to process.'
    Write-Host ' generatedDirectory - Directory for processed .lu files'
    Write-Host " destModelFolder - Directory that contains intent models (creates 'english' and 'multilingual' subfolders)."
    exit
}

Write-Output "`t appsettings.json: $appSettingsFile"
Write-Output "`t crossTrainedLUDirectory: $crossTrainedLUDirectory"
Write-Output "`t generatedDirectory: $generatedDirectory"
Write-Output "`t destModelFolder: $destModelFolder"

$models = Get-LUModels -recognizerType "Microsoft.OrchestratorRecognizer" -crossTrainedLUDirectory $crossTrainedLUDirectory -sourceDirectory $sourceDirectory

Write-Host "Orchestrator models"
foreach($model in $models)
{
    Write-Host "`t $model"
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

# Load appsettings.json
$appSettings = Get-Content -Path $appSettingsFile | ConvertFrom-Json

# Determine which models we need to download and train.
$useEnglishModel = $false
$useMultilingualModel = $false
Write-Output 'Loading appsettings...'
foreach ($language in $appSettings.languages) {
    if ($language.StartsWith('en')) {
        $useEnglishModel = $true
        Write-Output "`t Found English."
    }
    else {
        $useMultilingualModel = $true
        Write-Output "`t Found multilingual."
    }
}

# Create empty Composer config file for orchestrator.
$orchestratorConfig = "{
    orchestrator:{
        models:{},
        snapshots:{}
    }
}" | ConvertFrom-Json


# Download orchestrator models
if ($useEnglishModel) 
{
    # Download model and update config
    $modelDirectory = Get-OrchestratoModel -language "english" -modelDirectory "$generatedDirectory/orchestratorModels"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName en -NotePropertyValue (Get-NormalizedPath -path "$modelDirectory")

    # Build trained snapshots and update config
    Build-OrchestratorSnapshots -models $models -language "english" -modelDirectory $modelDirectory -outDirectory "$generatedDirectory" -luFilesDirectory $crossTrainedLUDirectory

}

if ($useMultilingualModel) 
{
    $modelDirectory = Get-OrchestratoModel -language "multilingual" -modelDirectory "$generatedDirectory/orchestratorModels"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName multilang -NotePropertyValue (Get-NormalizedPath -path "$modelDirectory")
}

Write-Output "Writing output file $generatedDirectory/orchestrator.settings.json"
$BLUFILES = Get-ChildItem -Path "$generatedDirectory" -Include *.blu -Name
foreach ($file in $BLUFILES) {
    $key = $file -replace ".{4}$"
    $key = $key.Replace(".", "_")
    $key = $key.Replace("-", "_")
    $orchestratorConfig.orchestrator.snapshots | Add-Member -NotePropertyName "$key" -NotePropertyValue (Get-NormalizedPath -path "$generatedDirectory/$file")
}

Write-Host ($orchestratorConfig | ConvertTo-Json)
$orchestratorConfig | ConvertTo-Json | Out-File -FilePath "$generatedDirectory/orchestrator.settings.json"
exit
if ($useEnglishModel) {
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
    bf orchestrator:build --in "$crossTrainedLUDirectory/english" --out "$generatedDirectory" --model "$destModelFolder/english"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName en -NotePropertyValue "$destModelFolder/english"
}

if ($useMultilingualModel) {
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
    bf orchestrator:build --in "$crossTrainedLUDirectory/multilingual" --out "$generatedDirectory" --model "$destModelFolder/multilingual"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName multilang -NotePropertyValue "$destModelFolder/multilingual"
}

Write-Output "Writing output file $generatedDirectory/orchestrator.settings.json"
$BLUFILES = Get-ChildItem -Path "$generatedDirectory" -Include *.blu -Name
foreach ($file in $BLUFILES) {
    $key = $file -replace ".{4}$"
    $key = $key.Replace(".", "_")
    $orchestratorConfig.orchestrator.snapshots | Add-Member -NotePropertyName "$key" -NotePropertyValue "$crossTrainedLUDirectory/$file"
}

$orchestratorConfig | ConvertTo-Json | Out-File -FilePath "$generatedDirectory/orchestrator.settings.json"