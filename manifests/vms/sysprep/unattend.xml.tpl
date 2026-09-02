<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

  <!--
    Windows Server 2022 specialization for the NSX policy demo.

    Rendered variables:
      __COMPUTER_NAME__
      __WINDOWS_PASSWORD__

    The PowerShell bootstrap is deliberately NOT embedded here. Windows
    FirstLogonCommands has a short CommandLine field, so the sysprep Secret
    also carries bootstrap.ps1 and this answer file invokes it from the
    attached sysprep CD-ROM.
  -->

  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <ComputerName>__COMPUTER_NAME__</ComputerName>
      <TimeZone>AUS Eastern Standard Time</TimeZone>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

      <!-- No interactive password prompt: Windows uses this generated lab
           password and AutoLogon signs Administrator in automatically. -->
      <AutoLogon>
        <Password>
          <Value>__WINDOWS_PASSWORD__</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>2</LogonCount>
        <Username>Administrator</Username>
      </AutoLogon>

      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p=(Get-PSDrive -PSProvider FileSystem | % {Join-Path $_.Root 'bootstrap.ps1'} | ? {Test-Path $_} | Select-Object -First 1); if($p){&amp; $p}else{exit 2}"</CommandLine>
          <Description>Configure NSX demo listeners</Description>
          <Order>1</Order>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
      </FirstLogonCommands>

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>

      <UserAccounts>
        <AdministratorPassword>
          <Value>__WINDOWS_PASSWORD__</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

    </component>
  </settings>
</unattend>
