
<p align="center"> 
  <img src="sextant.png" width="200px"> 
</p>

# Sextans Suite

Sextans Suite is software to support FAIR Metadata (Sextans Sight) and FAIR Data (Sextans Fix) authoring and publishing.

The sextant is an 18th-century navigational tool that uses celestial bodies and the horizon to determine location at sea. The constellation Sextans depicts a large astronomical sextant for naked-eye star measurements sharing the same 60-degree measuring concept.

## In the sea of data, navigation tools are critical!  

Sextans Sight creates a Metadata server following the FAIR Data Point specifications that provides automated agents with the ability to determine the utility of the contained resource (database, SKG, catalog, research object). The first step in navigation is deciding where you need to go!

Sextans Fix creates a set of tools for organizing and publishing data to facilitate their interpretation and integration by following FAIR and Semantic Web best-practies.  Once the weary traveller has arrived at their destination, give them nourishment!

## High-level Architecture

Sextans Sight should be deployed on a publicly-accessible server (e.g. in your Demilitarized Zone), and optimally has no access control - it acts like your institutional homepage, but for machines.

Sextans Fix is an optional second component that includes software for executing data transformations compatible with the [Clinical and Registry Entries Semantic Model (CARE-SM)](https://github.com/CARE-SM/).  Sextans Fix should be deployed inside of your firewall, and can only be accessed via tightly regulated calls from Sextans Sight (see detailed documentation below).

## CONTENTS

[Installing Sextans Sight](./Sextans/Sight-install/)

Installing Sextans Fix
