# InfusionPally
This addon allows you to track the cooldowns of a specific Paladin spell: Hand of Protection (also known as BoP/Blessing of Protection). Whenever a paladin in your raid uses them, it'll display their cooldowns so that you can work your gameplay around their availability, as well as requesting them with a simple click on your pally of choice.  
  
Particularly useful for whoever needs to request BoPs (mages, etc), paladins looking to track their fellow pallies and for raid leaders looking to track these cooldowns for ease of callouts.  
  
**INFUSIONPALLY REQUIRES SUPERWOW TO WORK!**
## Interface & Commands
Usage is as simple as it gets. Join a raid group and the tracker widgets will display automatically, even if you reload or restart the game while inside a raid group.  
To access the menu, click the BoP button on your minimap wheel, or type `/infusionpally` on your chat bar:  
  
![Menu](https://files.catbox.moe/wvoqbf.png)  
  
The **Help** button displays the available commands.  
**Clicking** any of the paladin names in the widgets will automatically whisper them requesting a BoP.  
  
![TrackersBig](https://files.catbox.moe/ozs0xs.png) ![TrackersSmol](https://files.catbox.moe/hhqkwj.png)  
  
Above is a comparison between the default and the 'Compact' widgets. Both have the same functionality.
### Commands
`/infusionpally`: opens/closes the main menu.  
`/infpwidget` or `/infpw`: opens placeholder tracker widgets for positioning configuration outside of a raid. Can not be used otherwise.  
`/infpclose` or `/infpc`: closes the tracking widgets. Can be used only if closing the configuration widgets OR if the raid does not have any druids in it.
## Extra Features
* The addon takes into account the Guardian's Favor talent and changes the cooldowns accordingly to match the correct CD, so don't worry about that.
* This addon also attempts to take mid-raid respecs into account without hindering performance by scanning the raid paladins every 10 minutes for talent changes. It'll adjust CDs accordingly. (may be changed later)
## Tips/Caveats
* If you disconnect or leave mid raid, the cooldowns **will reset**. This is unavoidable.
* It is likely that if you die and have to ghost run back while the raid is ongoing (read: they can't/won't res you and just continue pulling), you will miss CDs and cause the tracker to be inaccurate if they happen to use the spells during your runback. Try not to die, silly :>!
## Contributions
Welcome contributions of any kind, particularly those related to optimization. This was coded using Codex magic and a healthy dose of reviewing, but I'm nowhere near an expert in archaic 2004 Lua and can only do so much. If you read through and spot silly things that could be improved, let me know!  

Special thanks to **Cherrylane** for helping test so much of this addon, as well as **Ehawne** for being a huge (and critical) help in solving the talent tracking problem. Honorable mention to Raizan and other paladins for being there when quick tests were needed.
## To-do/Possible Additions
* possible automatic bopping on whisper if authorized by paladin with the addon
* checkmark for paladin users only to enable/disable autobop
* extra visual state display on tracking widgets (when dead, when out of range, when stunned, etc)
* bigwigs integration for resyncing in case of dc
