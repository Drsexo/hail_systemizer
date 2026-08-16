# Hail Systemizer

<p align="center">
  <a href="https://github.com/aistra0528/Hail"><img src="https://raw.githubusercontent.com/aistra0528/Hail/master/fastlane/metadata/android/en-US/images/icon.png" width="100" alt="Hail"></a>
</p>

Automated Magisk / KernelSU / APatch module that installs [Hail](https://github.com/aistra0528/Hail) as a **privileged system app** with a comprehensive `privapp-permissions` whitelist.

Hail runs Force Stop and Disable operations through the framework's hidden APIs directly, without spawning a `su` shell for every package. This is faster than Hail's Root working mode.

A GitHub Actions workflow rebuilds the module every Sunday from the latest successful Hail CI build. 