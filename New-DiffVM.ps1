#Requires -Module Hyper-V
#Requires -RunAsAdministrator
Function New-DiffVM {
<#
  .SYNOPSIS
  Creates a new local VM with a differencing disk

  .DESCRIPTION
  Creates a Hyper-V VM on the local machine with a differencing disk connected
  to a parent disk that should already exist.

  Create the parent VHDX by installing the Windows OS on a VM and then running Sysprep:
       sysprep.exe /generalize /oobe /mode:vm
  
  Delete the VM from the Hyper-V console and set the disk properties to read-only.
  This will become the parent disk, a template for one or more new VMs.

  .PARAMETER VMName
  The display name of the VM

  .PARAMETER RootFolder
  The parent folder of the new VM. A folder named after the VM will be created as a subfolder.

  .PARAMETER DiffParent
  The full path to the parent vhdx

  .PARAMETER SwitchName
  The name of the virtual switch to connect the Ethernet adapter to

  .PARAMETER MaxRam
  The maximum RAM used by dynamic memory e.g. 5120MB

  .PARAMETER MinRam
  The minimum RAM that dynamic memory will drop to e.g. 4096MB

  .PARAMETER Description
  Freeform text to populate the notes field with additional information

  .NOTES
  Version 1.0
#>
[cmdletbinding()]
param(
    [parameter(position=0,Mandatory)]
    [Alias("VM")]
    [ValidateNotNullOrEmpty()]
    [string]$VMName
    ,
    [parameter()]
    [ValidateScript({Test-path -path $_ -PathType Container})]
    [string]$VMFolder='C:\ProgramData\Microsoft\Windows\Hyper-V\Virtual Machines'
    ,
    [ValidateScript({Test-path -path $_ -PathType Container})]
    [string]$VHDFolder='C:\ProgramData\Microsoft\Windows\Virtual Hard Disks'
    ,
    [parameter()]
    [ValidateScript({Test-Path -Path $_ -PathType Leaf })]
    [string]$DiffParent = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\base_win11-24h2.vhdx'
    ,
    [parameter()]
    [ValidateScript({ (Get-VMSwitch -Name $_ | Select -ExpandProperty Name) -eq $_ })]
    [string]$SwitchName = 'internal'
    ,
    [parameter()]
    [ValidateNotNullOrEmpty()]
    [switch]$StartVM
    ,
    [parameter()]
    [ValidateNotNullOrEmpty()]
    [int64]$vCPUCount=4
    ,
    [parameter()]
    [ValidateNotNullOrEmpty()]
    [int64]$MaxRam=5120MB
    ,
    [parameter()]
    [ValidateNotNullOrEmpty()]
    [int64]$minRam=4096MB
    ,
    [string]$Description = "Created $(Get-Date -format 'yyyy-MM-dd') `nOS=Windows 11 `nDisk parent = '$DiffParent'"
)
PROCESS{

    # Adjust as required
     = (Get-WmiObject -class Win32_Processor | Select-Object -expand NumberOfLogicalProcessors)/2

    try{
        Write-Verbose "Creating VHD..."
        $VHD = New-VHD -Path "$VHDFolder\$($VMName).vhdx" -ParentPath $DiffParent -Differencing -ErrorAction Stop
        Start-Sleep -Seconds 3

        Write-Verbose "Creating VM..."
        New-VM -Name $VMName -VHDPath $VHD.Path -BootDevice VHD -Generation 2 -SwitchName $SwitchName | Out-Null

        Write-Verbose "Configuring VM..."
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MaximumBytes $MaxRam -MinimumBytes $MinRam -StartupBytes $MinRam -ErrorAction Stop
        Set-VM -Name $VMName -ProcessorCount $vCPUCount -CheckpointType Production -Notes $Description -AutomaticCheckpointsEnabled $False -ErrorAction Stop
        
        Write-Verbose "Enabling TPM..."
        $Owner = Get-HgsGuardian UntrustedGuardian
        $KP = New-HgsKeyProtector -Owner $Owner -AllowUntrustedRoot
        Set-VMKeyProtector -VMName $VMName -KeyProtector $KP.RawData
        Enable-VMTPM -VMName $VMName -ErrorAction Stop # required for Win11
    
        Write-Verbose "Enabling guest services..."
        Enable-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface' -ErrorAction Stop

        # Write-Verbose "Setting static MAC address..."
        # $MAC = '00-15-5D-{0:X}{1:X}-{2:X}{3:X}-{4:X}{5:X}' -f (Get-Random -Minimum 1 -Maximum 15), (Get-Random -Minimum 0 -Maximum 15), (Get-Random -Minimum 0 -Maximum 15), (Get-Random -Minimum 0 -Maximum 15), (Get-Random -Minimum 0 -Maximum 15), (Get-Random -Minimum 0 -Maximum 15)
        # $VMMac = $Mac.Replace('-','')
        # Set-VMNetworkAdapter -VMName $VMName -StaticMacAddress $VMMac -ErrorAction Stop
    }catch{
        Write-Warning "Failed to complete VM creation - '$_'"
        break
    }

    Write-Verbose "Taking snapshot..."
    Get-VM $VMName | Checkpoint-VM -SnapshotName "Initial"

    if($StartVM){
        Write-Verbose "Starting VM..."
        VMConnect localhost "$VMName"
        Start-Sleep -Seconds 2
        Start-VM $VMName
    }

    [PSCustomObject]@{
        VMName = $VMName
        Path = $RootFolder
        VHDPath = $VHD.Path
        ProcessorCount = $vCPUCount
        "MaximumRAM(MB)" = $($MaxRam / 1MB)
        "MinimumRAM(MB)" = $($minRam / 1MB)
    }

}

}

# New-DiffVM -VMName 'win11-1_24h2' -Verbose