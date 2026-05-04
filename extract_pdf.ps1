param([string]$PdfPath, [string]$OutPath, [int]$MaxPages = 30)

Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Load WinRT types
[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Foundation.IAsyncOperation`1,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null

# Helper to await async operations
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}
function AwaitAction($WinRtTask) {
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethod('AsTask', [Type[]]@([Windows.Foundation.IAsyncAction]))
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
}

# Open PDF
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($PdfPath)) ([Windows.Storage.StorageFile])
$pdf  = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])

$pageCount = [Math]::Min($pdf.PageCount, $MaxPages)
Write-Host "PDF has $($pdf.PageCount) pages, extracting $pageCount"

$ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$allText = [System.Text.StringBuilder]::new()

for ($i = 0; $i -lt $pageCount; $i++) {
    Write-Host "Processing page $($i+1)/$pageCount..."
    $page = $pdf.GetPage($i)
    
    # Render page to stream
    $ms = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
    $opts = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
    $opts.DestinationWidth = 1700
    AwaitAction ($page.RenderToStreamAsync($ms, $opts))
    
    # Decode image
    $ms.Seek(0)
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ms)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    
    # OCR
    $result = Await ($ocr.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    [void]$allText.AppendLine("=== PAGE $($i+1) ===")
    [void]$allText.AppendLine($result.Text)
    [void]$allText.AppendLine()
}

Set-Content $OutPath $allText.ToString() -Encoding UTF8
Write-Host "Done! Saved to $OutPath"
