﻿using module ..\Modules\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

if (-not $IsWindows -and -not $IsLinux) {return}
if ($IsLinux -and ($Global:GlobalCPUInfo.Vendor -eq "ARM" -or $Global:GlobalCPUInfo.Features.ARM)) {return} # No ARM binaries available
if (-not $Global:DeviceCache.DevicesByTypes.AMD -and -not $Global:DeviceCache.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

if ($IsLinux) {
    $Path = ".\Bin\GPU-OneZero\onezerominer"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v1.4.3-onezerominer/onezerominer-linux-1.4.3.tar.gz"
} else {
    $Path = ".\Bin\GPU-OneZero\onezerominer.exe"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v1.4.3-onezerominer/onezerominer-win64-1.4.3.zip"
}
$ManualUri = "https://github.com/OneZeroMiner/onezerominer/releases"
$Port = "370{0:d2}"
$DevFee = 3.0
$Cuda = "11.8"
$Version = "1.4.3"

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "dynex"; Params = ""; ExtendInterval = 5; DualZIL = $true; Fee = 2.0; Vendor = @("NVIDIA")} #DynexSolve/DNX
    [PSCustomObject]@{MainAlgorithm = "xelishashv2"; Params = ""; ExtendInterval = 3; Vendor = @("AMD","NVIDIA")} #XelisHashV2/XEL
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("AMD","NVIDIA")
        Name      = $Name
        Path      = $Path
        Port      = $Miner_Port
        Uri       = $Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
    }
    return
}

if ($Global:DeviceCache.DevicesByTypes.NVIDIA) {$Cuda = Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $Cuda -Warning $Name}

foreach ($Miner_Vendor in @("AMD","NVIDIA")) {
	$Global:DeviceCache.DevicesByTypes.$Miner_Vendor | Where-Object Type -eq "GPU" | Where-Object {$_.Vendor -ne "NVIDIA" -or $Cuda} | Select-Object Vendor, Model -Unique | ForEach-Object {
        $First = $true
        $Miner_Model = $_.Model
        $Miner_Device = $Global:DeviceCache.DevicesByTypes."$($_.Vendor)" | Where-Object {$_.Model -eq $Miner_Model}

        $ZilParams = if ($Miner_Vendor -eq "NVIDIA" -and $Session.Config.Pools.CrazyPool.EnableOneZeroMinerDual -and $Pools.ZilliqaCP) {
            if ($ZilWallet = $Pools.ZilliqaCP.Wallet) {
                " --a2 zil --w2 $($Pools.ZilliqaCP.User)$(if ($Pools.ZilliqaCP.Pass) {" --p2 $($Pools.ZilliqaCP.Pass)"}) --o2 $($Pools.ZilliqaCP.Protocol)://$($Pools.ZilliqaCP.Host):$($Pools.ZilliqaCP.Port) "
            }
        }

        $DisableCommand = if ($Miner_Vendor -eq "NVIDIA") {"--disable-amd"} else {"--disable-nvidia"}

        $Commands | Where-Object {$Miner_Vendor -in $_.Vendor} | ForEach-Object {

            $Algorithm_0 = if ($_.Algorithm) {$_.Algorithm} else {$_.MainAlgorithm}
            $Algorithm_Norm_0 = Get-Algorithm $Algorithm_0

		    foreach($Algorithm_Norm in @($Algorithm_Norm_0,"$($Algorithm_Norm_0)-$($Miner_Model)","$($Algorithm_Norm_0)-GPU")) {
			    if ($Pools.$Algorithm_Norm.Host -and $Miner_Device -and (-not $_.IncludePoolName -or $Pools.$Algorithm_Norm.Host -match $_.IncludePoolName)) {
                    if ($First) {
                        $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
                        $Miner_Name = (@($Name) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
                        $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ','
                        $First = $false
                    }
				    $Pool_Port = if ($Pools.$Algorithm_Norm.Ports -ne $null -and $Pools.$Algorithm_Norm.Ports.GPU) {$Pools.$Algorithm_Norm.Ports.GPU} else {$Pools.$Algorithm_Norm.Port}
				    [PSCustomObject]@{
					    Name           = $Miner_Name
					    DeviceName     = $Miner_Device.Name
					    DeviceModel    = $Miner_Model
					    Path           = $Path
					    Arguments      = "$($DisableCommand) -d $($DeviceIDsAll) -a $($_.MainAlgorithm) -w $($Pools.$Algorithm_Norm.User)$(if ($Pools.$Algorithm_Norm.Pass) {" -p $($Pools.$Algorithm_Norm.Pass)"}) -o $(if ($Pools.$Algorithm_Norm.SSL) {"$($Pools.$Algorithm_Norm.Protocol)://"})$($Pools.$Algorithm_Norm.Host):$($Pool_Port)$(if ($Pools.$Algorithm_Norm.Worker -and $Pools.$Algorithm_Norm.User -eq $Pools.$Algorithm_Norm.Wallet) {" --worker $($Pools.$Algorithm_Norm.Worker)"}) --api-port `$mport$(if ($_.DualZIL) {$ZilParams})$($_.Params)"
					    HashRates      = [PSCustomObject]@{$Algorithm_Norm = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".Week}
					    API            = "OneZeroMiner"
					    Port           = $Miner_Port
					    Uri            = $Uri
                        FaultTolerance = $_.FaultTolerance
					    ExtendInterval = $_.ExtendInterval
                        Penalty        = 0
					    DevFee         = if ($_.Fee -ne $null) {$_.Fee} else {$DevFee}
					    ManualUri      = $ManualUri
                        Version        = $Version
                        PowerDraw      = 0
                        BaseName       = $Name
                        BaseAlgorithm  = $Algorithm_Norm_0
                        Benchmarked    = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".Benchmarked
                        LogFile        = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".LogFile
                        EnvVars        = @()
				    }
			    }
		    }
        }
    }
}