# Script name:      check_ms_iis_application_pool.ps1
# Version:          v0.05.160609
# Created on:       10/03/2016
# Author:           Willem D'Haese
# Purpose:          Checks Microsoft Windows IIS application pool cpu and memory usage
# On Github:        https://github.com/willemdh/check_ms_iis_application_pool
# On OutsideIT:     https://outsideit.net/check-ms-iis-application-pool
# Recent History:
#   10/03/16 => Initial creation
#   06/04/16 => Added Run AppPoolOnDemand option - WRI
#   09/06/16 => Cleanup and formatting for release
# Copyright:
#   This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published
#   by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program is distributed 
#   in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
#   PARTICULAR PURPOSE. See the GNU General Public License for more details. You should have received a copy of the GNU General Public 
#   License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0

$DebugPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

$IISStruct = New-Object PSObject -Property @{
    StopWatch = [System.Diagnostics.Stopwatch]::StartNew();
    ApplicationPool = '';
    ProcessId = '';
    Process = '';
    PoolCount = '';
    PoolState = '';
    WarningMemory = '';
    CriticalMemory = '';
    WarningCpu = '';
    CriticalCpu = '';
    CurrentMemory = '';
    CurrentCpu = '';
    Duration = '';
    Exitcode = 3;
    AppPoolOnDemand = 0;
    ReturnString = 'UNKNOWN: Please debug the script...'
}

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$Log,
        [parameter(Mandatory=$true)][ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Unknown')][string]$Severity,
        [parameter(Mandatory=$true)][string]$Message
    )
    $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
    $LocalScriptName = split-path $MyInvocation.PSCommandPath -Leaf
    if ($Log -eq 'Undefined') {
        Write-Debug "${Now}: ${LocalScriptName}: Info: LogServer is undefined."
    }
    elseif ($Log -eq 'Verbose') {
        Write-Verbose "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -eq 'Debug') {
        Write-Debug "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -eq 'Output') {
        Write-Host "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -match '^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])(?::(?<port>\d+))$' -or $Log -match "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$") {
        $IpOrHost = $log.Split(':')[0]
        $Port = $log.Split(':')[1]
        if  ($IpOrHost -match '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$') {
            $Ip = $IpOrHost
        }
        else {
            $Ip = ([System.Net.Dns]::GetHostAddresses($IpOrHost)).IPAddressToString
        }
        Try {
            $LocalHostname = ([System.Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower()
            $JsonObject = (New-Object PSObject | 
                Add-Member -PassThru NoteProperty logsource $LocalHostname | 
                Add-Member -PassThru NoteProperty hostname $LocalHostname | 
                Add-Member -PassThru NoteProperty scriptname $LocalScriptName | 
                Add-Member -PassThru NoteProperty logtime $Now | 
                Add-Member -PassThru NoteProperty severity_label $Severity | 
                Add-Member -PassThru NoteProperty message $Message ) | 
                ConvertTo-Json
            $JsonString = $JsonObject -replace "`n",' ' -replace "`r",' '
            $Socket = New-Object System.Net.Sockets.TCPClient($Ip,$Port) 
            $Stream = $Socket.GetStream() 
            $Writer = New-Object System.IO.StreamWriter($Stream)
            $Writer.WriteLine($JsonString)
            $Writer.Flush()
            $Stream.Close()
            $Socket.Close()
        }
        catch {
            Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while trying to send message to Logstash server `"$Log`"."
        }
        Write-Verbose "${Now}: ${LocalScriptName}: ${Severity}: Ip: $Ip Port: $Port JsonString: $JsonString"
    }
    elseif ($Log -match '^((([a-zA-Z]:)|(\\{2}\w+)|(\\{2}(?:(?:25[0-5]|2[0-4]\d|[01]\d\d|\d?\d)(?(?=\.?\d)\.)){4}))(\\(\w[\w ]*))*)') {
        if (Test-Path -Path $Log -pathType container){
            Write-Host "${Now}: ${LocalScriptName}: Error: Passed Path is a directory. Please provide a file."
            exit 1
        }
        elseif (!(Test-Path -Path $Log)) {
            try {
                New-Item -Path $Log -Type file -Force | Out-null	
            } 
            catch { 
                $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
                Write-Host "${Now}: ${LocalScriptName}: Error: Write-Log was unable to find or create the path `"$Log`". Please debug.."
                exit 1
            }
        }
        try {
            "${Now}: ${LocalScriptName}: ${Severity}: $Message" | Out-File -filepath $Log -Append   
        }
        catch {
            Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while writing to file `"$Log`". It might be locked."
        }
    }
}

Function Initialize-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args
    )
    try {
        For ( $i = 0; $i -lt $Args.count; $i++ ) { 
            $CurrentArg = $Args[$i].ToString()
            if ($i -lt $Args.Count-1) {
                $Value = $Args[$i+1];
                If ($Value.Count -ge 2) {
                    foreach ($Item in $Value) {
                        Test-Strings $Item | Out-Null
                    }
                }
                else {
                    $Value = $Args[$i+1];
                    Test-Strings $Value | Out-Null
                }
            } 
            else {
                $Value = ''
            }
            switch -regex -casesensitive ($CurrentArg) {
                "^(-A|--ApplicationPool)$" {
                    if ($value -match "^[a-zA-Z0-9. _-]+$") {
                        $IISStruct.ApplicationPool = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-WM|--WarningMemory)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.WarningMemory = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-CM|--CriticalMemory)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.CriticalMemory = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-WC|--WarningCpu)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.WarningCpu = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-CC|--CriticalCpu)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.CriticalCpu = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-APOD|--AppPoolOnDemand)$" {
                    if ($value -match "^[0-1]{1,2}$") {
                        $IISStruct.AppPoolOnDemand = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }

                "^(-h|--Help)$" {
                    Write-Help
                }
                default {
                    throw "Illegal arguments detected: $_"
                 }
            }
        }
    } 
    catch {
        Write-Host "CRITICAL: Argument: $CurrentArg Value: $Value Error: $_"
        Exit 2
    }
}
Function Test-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    $BadChars=@("``", '|', ';', "`n")
    $BadChars | ForEach-Object {
        If ( $String.Contains("$_") ) {
            Write-Host "Error: String `"$String`" contains illegal characters."
            Exit $IISStruct.ExitCode
        }
    }
    Return $true
} 

Function Invoke-CheckIISApplicationPool {
    Try {
        Import-Module WebAdministration
        If (Get-ChildItem IIS:\AppPools | Where-Object {$_.Name -eq "$($IISStruct.ApplicationPool)"}) {
            $IISStruct.PoolState = Get-ChildItem IIS:\AppPools | Where-Object {$_.Name -eq "$($IISStruct.ApplicationPool)"} | Select-Object State -ExpandProperty State
            If ( $IISStruct.PoolState -eq 'Started') {
                $IISStruct.ProcessId = Get-WmiObject -NameSpace 'root\WebAdministration' -class 'WorkerProcess' | Where-Object {$_.AppPoolName -match $IISStruct.ApplicationPool}  | Select-Object -Expand ProcessId
                If ( $IISStruct.ProcessId ) {
                    $IISStruct.Process = get-wmiobject Win32_PerfFormattedData_PerfProc_Process | ? { $_.IdProcess -eq $IISStruct.ProcessId } 
                    $IISStruct.CurrentCpu = $IISStruct.Process.PercentProcessorTime
                    Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id: $($IISStruct.ProcessId) Percent CPU: $($IISStruct.CurrentCpu)"
                    $IISStruct.CurrentMemory = [Math]::Round(($IISStruct.Process.workingSetPrivate / 1MB),2)
                    Write-Log Verbose Info "Application pool $($IISStruct.ApplicationPool) process id: $($IISStruct.ProcessId) Private Memory: $($IISStruct.CurrentMemory)"
                    $Sites = Get-WebConfigurationProperty "/system.applicationHost/sites/site/application[@applicationPool='$($IISStruct.ApplicationPool)' and @path='/']/parent::*" machine/webroot/apphost -name name
                    $Apps = Get-WebConfigurationProperty "/system.applicationHost/sites/site/application[@applicationPool='$($IISStruct.ApplicationPool)' and @path!='/']" machine/webroot/apphost -name path
                    $IISStruct.PoolCount = ($Sites,$Apps | ForEach {$_.value}).count
                    $IISStruct.ExitCode = 0
                    $IISStruct.ReturnString = "OK: Application Pool `"$($IISStruct.ApplicationPool)`" with $($IISStruct.PoolCount) Applications. {CPU: $($IISStruct.CurrentCpu) %}{Memory: $($IISStruct.CurrentMemory) MB}"
                    $IISStruct.ReturnString += " | 'app_count'=$($IISStruct.PoolCount), 'pool_cpu'=$($IISStruct.CurrentCpu)%, 'pool_memory'=$($IISStruct.CurrentMemory)MB"
                }
                Else {
                    If ( $IISStruct.AppPoolOnDemand = 1 ) {
                        $IISStruct.Process = 0
                        $IISStruct.CurrentCpu  = 0
                        $IISStruct.CurrentMemory = 0
                        $Sites = 0
                        $Apps = 0
                        $IISStruct.PoolCount = 0
                        $IISStruct.ExitCode = 0
                        $IISStruct.ReturnString = "OK:  Application Pool Started but no process is assigned yet `"$($IISStruct.ApplicationPool)`" with 0 Applications. {CPU: 0%}{Memory: 0MB}"
                        $IISStruct.ReturnString += " | 'app_count'=0, 'pool_cpu'=0%, 'pool_memory'=0MB"
                    }
                    Else {
                        Throw "Application Pool `"$($IISStruct.ApplicationPool)`" not found in WMI."
                    }
                }
            }
            Else {
                Throw "Application Pool `"$($IISStruct.ApplicationPool)`" is $($IISStruct.PoolState)."       
            }
        }
        Else {
            Throw "Application Pool `"$($IISStruct.ApplicationPool)`" does not exist."
        }
    }
    Catch {
        $IISStruct.ExitCode = 2
        $IISStruct.ReturnString = "CRITICAL: $_"
    }
}

#endregion Functions

#region Main

if ($Args) {
    if($Args[0].ToString() -ne "$ARG1$" -and $Args.count -ge 2){
            Initialize-Args $Args
            Invoke-CheckIISApplicationPool
    }
    else {
        $IISStruct.ReturnString = 'CRITICAL: Script needs mandatory parameters to work.'
        $IISStruct.ExitCode = 2
    }
}
Write-Host $IISStruct.ReturnString
Exit $IISStruct.ExitCode

#endregion Main

