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
            $luModels += $luModel
        }
    }

    # return the models found
    return $luModels
}