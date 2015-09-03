﻿#requires -Version 2 -Modules Hyper-V, Storage

function Initialize-VHDPartition
{
    <#
            .Synopsis
            Create VHD(X) with partitions needed to be bootable
            .DESCRIPTION
            This command will create a VHD or VHDX file. 

            To create a recovery partition use -Recovery

            .EXAMPLE
            Initialize-VHDPartition d:\disks\disk001.vhdx -dynamic -size 30GB
            .EXAMPLE
            Initialize-VHDPartition d:\disks\disk001.vhdx -dynamic -size 40GB -Recovery
            .NOTES
            General notes
    #>
    [CmdletBinding(SupportsShouldProcess = $true, 
            PositionalBinding = $false,
    ConfirmImpact = 'Medium')]
    Param
    (
        # Path to the new VHDX file (Must end in .vhdx)
        [Parameter(Position = 0,Mandatory = $true,
        HelpMessage = 'Enter the path for the new VHDX file')]
        [ValidateNotNullorEmpty()]
        [ValidatePattern(".\.vhdx?$")]
        [ValidateScript({
                    if (get-FullFilePath -Path $_ |
                        Split-Path  |
                    Resolve-Path ) 
                    {
                        $true
                    }
                    else 
                    {
                        Throw "Parent folder for $_ does not exist."
                    }
        })]
        [string]$Path,
        
        # Size in Bytes (Default 40B)
        [ValidateRange(25GB,64TB)]
        [uint64]$Size = 40GB,
        
        # Create Dynamic disk
        [switch]$Dynamic,

        # Block Size (Default 2MB)
        #[UInt32]$BlockSizeBytes = 2MB,

        # Specifies whether to create a VHD or VHDX formatted Virtual Hard Disk.
        # The default is AUTO, which will create a VHD if using the BIOS disk layout or 
        # VHDX if using UEFI or WindowsToGo layouts.
        [Alias('Format')]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('VHD', 'VHDX', 'AUTO')]
        $VHDFormat        = 'AUTO',

        # Specifies whether to build the image for BIOS (MBR), UEFI (GPT), or WindowsToGo (MBR).
        # Generation 1 VMs require BIOS (MBR) images.  Generation 2 VMs require UEFI (GPT) images.
        # Windows To Go images will boot in UEFI or BIOS
        [Parameter(Mandatory = $true)]
        [Alias('Layout')]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('BIOS', 'UEFI', 'WindowsToGo')]
        $DiskLayout,

        
        # Output the disk image object
        [switch]$Passthru,
         
        # Create the Recovery Enviroment Tools Partition. Not valid for VHD
        [switch]$RecoveryTools,

        # Create the Recovery Enviroment Tools and Recovery Image Partitions. Not valid for VHD
        [switch]$RecoveryImage,

        # Force the overwrite of existing files
        [switch]$force
    )
    Begin { 

        #region Validate input

        # Recovery Image requires the Recovery Tools
        if ($RecoveryImage) 
        {
            $RecoveryTools = $true
        }

        # resolved Format
        if ($VHDFormat -ilike 'AUTO')
        {
            if ($DiskLayout -eq 'BIOS')
            {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Validating : Dislayout [$DiskLayout] Setting Format to VHD"
                $VHDFormat = 'VHD'
            }
            else
            {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Validating : Dislayout [$DiskLayout] Setting Format to VHDX"
                $VHDFormat = 'VHDX'
            }
        }
          
        $ext = ([IO.FileInfo]$Path).Extension
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Validating : [$ext] like [.$VHDFormat]"
        if ($ext -inotlike ".$($VHDFormat)")
        {
            throw "The file extention in [$Path] does not match format [.$VHDFormat]"
        } 
          
        # Choose smallest supported block size for dynamic VHD(X)
        $BlockSize = 1MB

        # Enforce max VHD size.
        if ('VHD' -ilike $VHDFormat) 
        {
            if ($Size -gt 2040GB) 
            {
                Write-Warning -Message 'For the VHD file format, the maximum file size is ~2040GB.  Reseting size to 2040GB.'
                $Size = 2040GB
            }

            $BlockSize = 512KB
        }

        $SysSize = 200MB
        $MSRSize = 128MB
        $RESize = 0 
        $RecoverySize = 0
        if ($RecoveryTools)
        {
            $RESize = 300MB
        }
        if ($RecoveryImage)
        {
            $RecoverySize = 15GB
        }
        #if ($RecoveryTools -or $RecoveryImage)
        #{
        #    $OSSize = $Size - $SysSize - $MSRSize - $RESize - $RecoverySize
        #    Write-Verbose "[$($MyInvocation.MyCommand)] Validating : Recovery Partition Requested OS partition set to [$OSSize] Bytes"
        #}
        else 
        {

        }
        $fileName = Split-Path -Leaf -Path $Path
    
        # make paths absolute
        $Path = $Path | get-FullFilePath
        #endregion

        if ($pscmdlet.ShouldProcess("$Path", 'Create partition structure for Bootable disks'))
        {
            if((-not (Test-Path $Path)) -Or 
                $force -Or 
            ((Test-Path $Path) -and $pscmdlet.ShouldContinue("TargetFile [$Path] exists! Any existin data will be lost!", 'Warning'))) 
            {
                # if we get this far it's ok to delete existing files
                if (Test-Path -Path $Path) 
                {
                    Remove-Item -Path $Path
                }
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Creating"
            
                #region Create VHD 
                Try 
                {
                    if ($VHDCmdlets)
                    {
                        $vhdParams = @{
                            ErrorAction = 'Stop'
                            Path        = $Path
                            SizeBytes   = $Size
                            Dynamic     = $Dynamic
                        }
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : @vhdParms"
                        Write-Verbose -Message ($vhdParams | Out-String)
                        $null = New-VHD @vhdParams
                    }
                    else 
                    {
                        # $VHDFormat = 'VHDX'

                        $vhdParams = @{
                            VHDFormat = $VHDFormat
                            Path      = $Path
                            SizeBytes = $Size
                        }

                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Params for [WIM2VHD.VirtualHardDisk]::CreateSparseDisk()"
                        Write-Verbose -Message ($vhdParams | Out-String)
                        
                        
                        [WIM2VHD.VirtualHardDisk]::CreateSparseDisk(
                            $VHDFormat,
                            $Path,
                            $Size,
                            $true
                        )
                    } 
                } 
                catch
                {
                    Throw "Failed to create $Path. $($_.Exception.Message)"
                }
                  
                #endregion
                
                
                
                if (Test-Path -Path $Path) 
                {
                    #region Mount Image
                    try 
                    {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Mounting disk image"
                        $disk = Mount-DiskImage -ImagePath $Path -PassThru |
                        Get-DiskImage |
                        Get-Disk
                    }
                    catch 
                    {
                        throw $_.Exception.Message
                    }
                    #endregion

                    #region create partitions
                    try
                    {
                        $disknumber = $disk.Number

                        switch ($DiskLayout)            
                        {             
                            'BIOS' 
                            {
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Initializing disk [$disknumber] as MBR"
                                Initialize-Disk -Number $disknumber -PartitionStyle MBR

                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Clearing disk partitions to start all over"
                                Get-Disk -Number $disknumber -ErrorAction Stop |
                                Get-Partition -ErrorAction Stop |
                                Remove-Partition -Confirm:$false -ErrorAction Stop

                                # Create the Windows/system partition 
                                # Refresh $disk to update free space
                                $disk = Get-DiskImage -ImagePath $Path | Get-Disk
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Creating single partition of [$($disk.LargestFreeExtent)] bytes"
                                $windowsPartition = New-Partition -DiskNumber $disknumber -UseMaximumSize -MbrType IFS -IsActive #-Size $disk.LargestFreeExtent
                                $systemPartition = $windowsPartition
    
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Formatting windows volume"
                                $windowsVolume = Format-Volume -Partition $windowsPartition -FileSystem NTFS -Force -Confirm:$false
                                $systemVolume = $windowsVolume
                            } 
                
                            'UEFI' 
                            {
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Initializing disk [$disknumber] as GPT"
                                Initialize-Disk -Number $disk.Number -PartitionStyle GPT

                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Clearing disk partitions to start all over"
                                Get-Disk -Number $disknumber -ErrorAction Stop |
                                Get-Partition -ErrorAction Stop |
                                Remove-Partition -Confirm:$false -ErrorAction Stop

                                if ($RecoveryTools)
                                {
                                    Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Recovery tools : Creating partition of [$RESize] bytes"
                                    $recoveryToolsPartition = New-Partition -DiskNumber $disk.Number -Size $RESize -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
                                    Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Recovery tools : Formatting NTFS"
                                    $recoveryToolsVolume = Format-Volume -Partition $recoveryToolsPartition -FileSystem NTFS -NewFileSystemLabel 'Windows RE Tools' -Force -Confirm:$false
                                    #run diskpart to set GPT attribute to prevent partition removal
                                    #the here string must be left justified
                                    $null = @"
select disk $($disk.Number)
select partition $($recoveryToolsPartition.partitionNumber)
gpt attributes=0x8000000000000001
exit
"@ |
                                    diskpart.exe
                                }
                    
                    
                                # Create the system partition.  Create a data partition so we can format it, then change to ESP
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : EFI system : Creating partition of [$SysSize] bytes"
                                $systemPartition = New-Partition -DiskNumber $disk.Number -Size $SysSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
                
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : EFI system : Formatting FAT32"
                                $windowsVolume = Format-Volume -Partition $systemPartition -FileSystem FAT32 -Force -Confirm:$false

                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : EFI system : Setting system partition as ESP"
                                $systemPartition | Set-Partition -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
                
                                # Create the reserved partition 
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : MSR : Creating partition of [$MSRSize] bytes"
                                $reservedPartition = New-Partition -DiskNumber $disk.Number -Size $MSRSize -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
        
                    
                                # Create the Windows partition
                                # Refresh $disk to update free space
                                $disk = Get-DiskImage -ImagePath $Path | Get-Disk
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Windows : Creating partition of [$($disk.LargestFreeExtent - $RecoverySize)] bytes"
                                $windowsPartition = New-Partition -DiskNumber $disk.Number -Size ($disk.LargestFreeExtent - $RecoverySize) -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Windows : Formatting volume NTFS"
                                $windowsVolume = Format-Volume -Partition $windowsPartition -NewFileSystemLabel 'OS' -FileSystem NTFS -Force -Confirm:$false
                    
                                if ($RecoveryImage)
                                {
                                    Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Recovery Image : Creating partition useing remaing free space"
                                    $recoveryImagePartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
                                    Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Recovery Image : Formatting volume NTFS"
                                    $RecoveryImageVolume = Format-Volume -Partition $recoveryImagePartition -NewFileSystemLabel 'Windows Recovery' -FileSystem NTFS -Force -Confirm:$false
                                    #run diskpart to set GPT attribute to prevent partition removal
                                    #the here string must be left justified
                                    $null = @"
select disk $($disk.Number)
select partition $($recoveryImagePartition.partitionNumber)
gpt attributes=0x8000000000000001
exit
"@ |
                                    diskpart.exe
                                }
                            }

                            'WindowsToGo' 
                            {                
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Initializing disk [$disknumber] as MBR"
                                Initialize-Disk -Number $disk.Number -PartitionStyle MBR
                    
                                Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Clearing disk partitions to start all over"
                                Get-Disk -Number $disknumber -ErrorAction Stop |
                                Get-Partition -ErrorAction Stop |
                                Remove-Partition -Confirm:$false -ErrorAction Stop
                
                                # Create the system partition 
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : System : Creating partition of [$SysSize] bytes"
                                $systemPartition = New-Partition -DiskNumber $disk.Number -Size $SysSize -MbrType FAT32 -IsActive 
        
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : EFI system : Formatting FAT32"
                                $systemVolume    = Format-Volume -Partition $systemPartition -FileSystem FAT32 -Force -Confirm:$false
            
                                # Create the Windows partition
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Windows : Creating partition useing remaning space"
                                $windowsPartition = New-Partition -DiskNumber $disk.Number -Size $disk.LargestFreeExtent -MbrType IFS
        
                                Write-Verbose "[$($MyInvocation.MyCommand)] [$fileName] : Windows : Formatting volume NTFS"
                                $windowsVolume    = Format-Volume -Partition $windowsPartition -FileSystem NTFS -Force -Confirm:$false
                            }
                        }
                    }
                    catch 
                    {
                        Write-Error -Message "[$($MyInvocation.MyCommand)] [$fileName] : Creating Partitions"
                        throw $_.Exception.Message
                    }
                    #endregion create partitions
                
                    #region Dismount
                    finally 
                    {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] [$fileName] : Dismounting disk image"
                        Dismount-DiskImage -ImagePath $Path 
                    }
                    #endregion
                    
                    if ($Passthru)
                    {
                        #write the new disk object to the pipeline
                        Get-DiskImage -ImagePath $Path
                    }
                }#end if disk
                else 
                {
                    throw "Unable to create or mount $Path"
                }
            }
        }
    }
}
