$formatter = {
	$args[0].ToString( "yyyy'-'MM'-'dd'T'HH':'mm':'ssK" );
};
$now = [datetime]::UtcNow;
$start = & $formatter $now;
$end = & $formatter $now.AddDays( 365 );

$params = @{
	LiteralPath = 'Registry::HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings';
	Type = 'String';
	Force = $true;
};

$paramsDWORD = @{
	LiteralPath = 'Registry::HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings';
	Type = 'DWORD';
	Force = $true;
};

New-ItemProperty @paramsDWORD -Name 'FlightSettingsMaxPauseDays' -Value 0x00001c84;
Set-ItemProperty @params -Name 'PauseFeatureUpdatesStartTime' -Value $start;
Set-ItemProperty @params -Name 'PauseFeatureUpdatesEndTime' -Value $end;
Set-ItemProperty @params -Name 'PauseQualityUpdatesStartTime' -Value $start;
Set-ItemProperty @params -Name 'PauseQualityUpdatesEndTime' -Value $end;
Set-ItemProperty @params -Name 'PauseUpdatesStartTime' -Value $start;
Set-ItemProperty @params -Name 'PauseUpdatesExpiryTime' -Value $end;

# Create scheduled task to run this script monthly
$taskName = "Pause-WindowsUpdate"
$scriptPath = $MyInvocation.MyCommand.Path

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $existingTask) {
    Write-Host "Creating scheduled task: $taskName"
    
    # Define the action (run this PowerShell script)
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    
    # Define the trigger (run weekly every Monday at 3 AM - closest to monthly that's supported)
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 3am
    
    # Define additional triggers for startup and daily (as backup)
    $triggerStartup = New-ScheduledTaskTrigger -AtStartup
    $triggerDaily = New-ScheduledTaskTrigger -Daily -At 3am
    
    # Combine all triggers
    $allTriggers = @($trigger, $triggerStartup, $triggerDaily)
    
    # Define the principal (run as SYSTEM with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Define settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
    
    # Register the scheduled task
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $allTriggers -Principal $principal -Settings $settings -Description "Automatically pauses Windows Updates for 1 year to prevent unwanted reboots during work hours"
        Write-Host "Successfully created scheduled task: $taskName"
    }
    catch {
        Write-Error "Failed to create scheduled task: $($_.Exception.Message)"
    }
}
else {
    Write-Host "Scheduled task '$taskName' already exists"
}