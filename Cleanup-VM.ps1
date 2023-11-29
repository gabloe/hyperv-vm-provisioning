<#
.SYNOPSIS
    Stop VM and remove all resources
.EXAMPLE
    PS C:\> .\Cleanup-VM "VM1","VM2" [-Force]
#>

[CmdletBinding()]
param(
    [string[]] $VMNames = @(),
    [switch] $Force = $false,
    [string] $RemoteServerIP,
    [pscredential] $Credential
)

function Cleanup-VM([string]$vmName, [Microsoft.Management.Infrastructure.CimSession]$session = $null) {
    Write-Verbose "Trying to stop $vmName ..."
    $stopParams = @{
        VMName = $vmName
        TurnOff = $true
        Confirm = $false
        ErrorAction = 'SilentlyContinue'
    }
    if ($session) {
        $stopParams['CimSession'] = $session
    }
    Stop-VM @stopParams | Out-Null

    # Additional cleanup operations
    # Add -CimSession $session to each cmdlet if $session is not null
    if($session) {
        Write-Host "Cleaning up $vmName from remote host..."
        # remove snapshots
        Remove-VMSnapshot -VMName $vmName -CimSession $session -IncludeAllChildSnapshots -ErrorAction SilentlyContinue
        # remove disks
        Get-VM -VMName $vmName  -CimSession $session -ErrorAction SilentlyContinue | ForEach-Object {
            $_.id | get-vhd  -CimSession $session -ErrorAction SilentlyContinue | ForEach-Object {
                remove-item -path $_.path -force -ErrorAction SilentlyContinue
            }
        }
        #remove cloud-init metadata iso
        $VHDPath = (Get-VMHost  -CimSession $session).VirtualHardDiskPath
        Remove-Item -Path "$VHDPath$vmName-metadata.iso" -ErrorAction SilentlyContinue
        # remove vm
        Remove-VM -VMName $vmName  -CimSession $session -Force -ErrorAction SilentlyContinue | Out-Null
    }
    else {
        Write-Host "Cleaning up $vmName..."
        # remove snapshots
        Remove-VMSnapshot -VMName $vmName -IncludeAllChildSnapshots -ErrorAction SilentlyContinue
        # remove disks
        Get-VM -VMName $vmName -ErrorAction SilentlyContinue | ForEach-Object {
            $_.id | get-vhd -ErrorAction SilentlyContinue | ForEach-Object {
                remove-item -path $_.path -force -ErrorAction SilentlyContinue
            }
        }
        #remove cloud-init metadata iso
        $VHDPath = (Get-VMHost).VirtualHardDiskPath
        Remove-Item -Path "$VHDPath$vmName-metadata.iso" -ErrorAction SilentlyContinue
        # remove vm
        Remove-VM -VMName $vmName -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

$session = $null
if ($RemoteServerIP -and $Credential) {
    Write-Host "Creating a new session to clean up VM..."
    $session = New-CimSession -ComputerName $RemoteServerIP -Credential $Credential
}

if ($Force -or $PSCmdlet.ShouldContinue("Are you sure you want to delete VM?", "Data purge warning")) {
    if ($VMNames.Count -gt 0) {
        Write-Host "Stop and delete VM's and its data files..." -NoNewline

        foreach ($vmName in $VMNames) {
            Cleanup-VM -vmName $vmName -session $session
        }
    }
}

if ($session) {
    Remove-CimSession -CimSession $session
}

Write-Host -ForegroundColor Green " Done."