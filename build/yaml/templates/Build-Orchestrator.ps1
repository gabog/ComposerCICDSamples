# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
# 
# Builds and trains 
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
	[string] $generatedDirectory
)

# Import script with common functions
. ($PSScriptRoot + "/LUUtils.ps1")

if ($PSBoundParameters.Keys.Count -lt 5) {
    Write-Host "Dowload models and trains orchestrator" 
    Write-Host 'Usage: OrchestratorCICD.ps1 appsettings.json crossTrainedLUDirectory generatedDirectory modelsDirectory'
    Write-Host 'Parameters: '
    Write-Host ' appsettings.json - Bot appsettings.json file.'
    Write-Host ' crossTrainedLUDirectory - Directory containing .lu/.qna files to process.'
    Write-Host ' generatedDirectory - Directory for processed .lu files'
    exit
}

Write-Output "`t appsettings.json: $appSettingsFile"
Write-Output "`t crossTrainedLUDirectory: $crossTrainedLUDirectory"
Write-Output "`t generatedDirectory: $generatedDirectory"

# Find the lu models for the dialogs configured to use orchestrator
$models = Get-LUModels -recognizerType "Microsoft.OrchestratorRecognizer" -crossTrainedLUDirectory $crossTrainedLUDirectory -sourceDirectory $sourceDirectory
if ($models.Count -eq 0)
{
    Write-Host "No orchestrator models found."
    exit 0        
}
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

# Create empty Composer config file for orchestrator settings.
$orchestratorConfig = "{
    orchestrator:{
        models:{},
        snapshots:{}
    }
}" | ConvertFrom-Json


# Download English model and build snapshots
if ($useEnglishModel) 
{
    # Download model and update config
    $modelDirectory = Get-OrchestratoModel -language "english" -modelDirectory "$generatedDirectory/orchestratorModels"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName en -NotePropertyValue (Get-NormalizedPath -path "$modelDirectory")

    # Build snapshots
    Build-OrchestratorSnapshots -models $models -language "english" -modelDirectory $modelDirectory -outDirectory "$generatedDirectory" -luFilesDirectory $crossTrainedLUDirectory

}

# Download multilanguage model and build snapshots
if ($useMultilingualModel) 
{
    # Download model and update config
    $modelDirectory = Get-OrchestratoModel -language "multilingual" -modelDirectory "$generatedDirectory/orchestratorModels"
    $orchestratorConfig.orchestrator.models | Add-Member -NotePropertyName multilang -NotePropertyValue (Get-NormalizedPath -path "$modelDirectory")

    # Build snapshots and update config
    Build-OrchestratorSnapshots -models $models -language "multilingual" -modelDirectory $modelDirectory -outDirectory "$generatedDirectory" -luFilesDirectory $crossTrainedLUDirectory
}

# Update and write config file
Write-Output "Writing output file $generatedDirectory/orchestrator.settings.json"
$bluFiles = Get-ChildItem -Path "$generatedDirectory" -Include *.blu -Name
foreach ($bluFile in $bluFiles) 
{
    # Update the key name so composer can recognize (remove the extension, replace . and - by _)
    $key = $bluFile -replace ".{4}$"
    $key = $key.Replace(".", "_")
    $key = $key.Replace("-", "_")
    $orchestratorConfig.orchestrator.snapshots | Add-Member -NotePropertyName "$key" -NotePropertyValue (Get-NormalizedPath -path "$generatedDirectory/$bluFile")
}

Write-Host ($orchestratorConfig | ConvertTo-Json)
$orchestratorConfig | ConvertTo-Json | Out-File -FilePath "$generatedDirectory/orchestrator.settings.json"
