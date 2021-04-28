# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
# 
# Contains a collection of common language understanding functions used in other scripts.
#

# Gets the list of lu models for a given recognizer
function Get-LUModels
{
    param 
    (
        [string] $recognizerType,
        [string] $crossTrainedLUDirectory,
        [string] $sourceDirectory
    )

    # Get a list of the cross trained lu models to process
    $crossTrainedLUModels = Get-ChildItem -Path $crossTrainedLUDirectory -Filter "*.lu" -file -name

    # Get a list of all the dialog recognizers (exclude bin and obj just in case)
    $luRecognizerDialogs = Get-ChildItem -Path $sourceDirectory -Filter "*??-??.lu.dialog" -file -name -Recurse | Where-Object { $_ -notmatch '^bin*|^obj*' }

    # Add the models that matche the type to the recognizers to a list
    $luModels = @()
    foreach($luModel in $crossTrainedLUModels) {
        # Load the dialog JSON and find the recognizer kind
        $luDialog = $luRecognizerDialogs | Where-Object { $_ -match "$luModel.dialog" }
        $dialog = Get-Content -Path "$sourceDirectory/$luDialog" | ConvertFrom-Json
        $recognizerKind = ($dialog | Select -ExpandProperty "`$kind")

        # Add it to the list if it is the expected type
        if ( $recognizerKind -eq $recognizerType)
        {
            $luModels += "$crossTrainedLUDirectory/$luModel"
        }
    }

    # return the models found
    return $luModels
}

# Downloads the orchestrator models based on the languages configured in appsettings.json
function Get-OrchestratoModel
{
    param 
    (
        [string] $language,
        [string] $modelDirectory
    )
    
    # Clean and recreate the model directory
    $outDirectory = "$modelDirectory/$language"
    if ((Test-Path -Path "$outDirectory") -eq $true) 
    {
        Remove-Item -Path "$outDirectory" -Force -Recurse | Out-Null
    }
    Write-Host "Creating $outDirectory folder..."
    New-Item -Path "$outDirectory" -ItemType "directory" -Force | Out-Null
    Write-Host "done."

    # We only support english and multilingual for now
    if ($language -eq "english")
    {
        bf orchestrator:basemodel:get -o "$outDirectory" | Out-Null
    }
    else
    {
        bf orchestrator:basemodel:get -o "$outDirectory" --versionId pretrained.20210205.microsoft.dte.00.06.unicoder_multilingual.onnx | Out-Null
    }

    return $outDirectory
}

# Builds and trains orchestrator snapshots (blu files)
function Build-OrchestratorSnapshots
{
    param 
    (
        $models,
        [string] $language,
        [string] $modelDirectory,
        [string] $outDirectory,
        [string] $luFilesDirectory

    )

    $luModels = @()
    if ($language -eq "english")
    {
        $luModels = Get-ChildItem $models -Include "*en*.lu" -Name
    }
    else
    {
        $luModels = Get-ChildItem $models -Exclude "*en*.lu" -Name
    }

    # Create folder to store input lu files
    $inputDirectory = "$modelDirectory/input"
    if ((Test-Path -Path "$inputDirectory") -eq $false) 
    {
        New-Item -Path "$inputDirectory" -ItemType "directory" -Force | Out-Null
    }

    # Copy cross trained lu files to input directory
    foreach ($luModel in $luModels)
    {
        Copy-Item -Path "$luFilesDirectory/$luModel" -Destination "$inputDirectory/$luModel" -Force | Out-Null
    }

    # Train
    bf orchestrator:build --in "$inputDirectory" --out "$outDirectory" --model "$modelDirectory"
}

# Helper to replace \ by / so it works on linux and windows
function Get-NormalizedPath
{
    param 
    (
        [string] $path
    )
    return $path.Replace("\", "/")
}
