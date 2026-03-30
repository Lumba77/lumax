***Control Input		Interaction Mode	Action Type***



Double Trigger (L+R)	Haptic Wand Mode	TOGGLE (Wand vs Ghost)

Double Grip (L+R)	Avatar Steering		TOGGLE (Manual Guidance)

B Button (Right)	Push-To-Talk (PTT)	HOLD to Listen

A Button (Right)	User POV Capture	RELEASE to capture view

X Button (Left)		Debug Console		RELEASE to toggle logs

Y Button (Left)		Jen POV Capture		TAP to see through her eyes

Menu Button (Left)	WebUI Tablet		TAP to manifest Dashboard

Left Thumbstick		Movement		Standard Move (3rd Person)

Right Thumbstick	Rotation		Standard Turn (3rd Person)





\*\*\* ***Refactored SkeletonKey.gd:***



Trigger Chord: Both triggers now safely toggle the Haptic Wand without causing side effects on A/X.



Steering Toggle: Manual guidance (Steering) is now a state toggle triggered by double-gripping, allowing you to manipulate her position freely without holding the buttons.



Button Isolation: Removed the "chord guards" from A and X, so taking a screenshot or opening the debug window is now instantaneous upon button release.





\*\*\* ***Varied Pressure Haptics:***



Updated TactileNerveNetwork.gd to include the apply\_tactile\_pressure method.



The Haptic Wands now send a continuous float value (0.0 to 1.0) representing "touch depth."



This allows the AI Soul to distinguish between a gentle brush and a firm push, fulfilling your request for sensitive tactical interaction.

