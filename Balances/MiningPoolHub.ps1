﻿using module ..\Include.psm1

param(
    $Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$PoolConfig = $Config.Pools.$Name

if(!$PoolConfig.API_Key) {
    Write-Log -Level Verbose "Cannot get balance on pool ($Name) - no API key specified. "
    return
}

$Request = [PSCustomObject]@{}

# Get user balances
try {
    $Request = Invoke-RestMethod "http://miningpoolhub.com/index.php?page=api&action=getuserallbalances&api_key=$($PoolConfig.API_Key)" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Warning "Pool Balance API ($Name) has failed. "
    return
}

if (($Request.getuserallbalances.data | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool Balance API ($Name) returned nothing. "
    return
}

$Request.getuserallbalances.data | Foreach-Object {

    #Define currency
    $Currency = $_.coin
    try {
        $Currency = Invoke-RestMethod "http://$($_.coin).miningpoolhub.com/index.php?page=api&action=getpoolinfo&api_key=$($PoolConfig.API_Key)" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Select-Object -ExpandProperty getpoolinfo | Select-Object -ExpandProperty data | Select-Object -ExpandProperty currency 
    }
    catch {
        Write-Log -Level Warn "Cannot determine currency for coin ($($_.coin)) - cannot convert some balances to BTC or other currencies. "
    }

    [PSCustomObject]@{
        Caption     = "$($Name) ($($Currency))"
        Currency    = $Currency
        Balance     = $_.confirmed
        Pending     = $_.unconfirmed + $_.ae_confirmed + $_.ae_unconfirmed + $_.exchange
        Total       = $_.confirmed + $_.unconfirmed + $_.ae_confirmed + $_.ae_unconfirmed + $_.exchange
        Lastupdated = (Get-Date).ToUniversalTime()
    }
}