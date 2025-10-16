# School of Computing &mdash; Year 4 Project Proposal Form

> Edit (then commit and push) this document to complete your proposal form.
> Make use of figures / diagrams where appropriate.
>
> Do not rename this file.

## SECTION A

|                     |                   |
|---------------------|-------------------|
|Project Title:       | Super Tag         |
|Student 1 Name:      | Luan Slankster    |
|Student 1 ID:        | 22406536          |
|Student 2 Name:      | xxxxxx            |
|Student 2 ID:        | xxxxxx            |
|Project Supervisor:  | Darragh O'Brien   |

> Ensure that the Supervisor formally agrees to supervise your project; this is only recognised once the
> Supervisor assigns herself/himself via the project Dashboard.
>
> Project proposals without an assigned
> Supervisor will not be accepted for presentation to the Approval Panel.

## SECTION B

> Guidance: This document is expected to be approximately 3 pages in length, but it can exceed this page limit.
> It is also permissible to carry forward content from this proposal to your later documents (e.g. functional
> specification) as appropriate.
>
> Your proposal must include *at least* the following sections.


### Introduction

> Describe the general area covered by the project.

> Super Tag aims to facilitate playing of the well-known game of tag but on a much larger scale than usual. Instead of 
> running around your primary school playground, this game is designed to be played in much larger spaces like an entire 
> park. The area the players will play in will be split into sections. The person who begins as "it" can close a section
> around every 15 minutes making it so players cannot be in that section. When caught, a player will join the "it" team 
> and the last person caught will win. 

### Outline

> Outline the proposed project.
> To achieve the previously described goal, Super Tag will implement the following features:

- Roles
> Players can select "it" or "not it" when starting the game. A player can switch to "it" at anytime during the game i.e. when
> they are caught but can only select "not it" when the game begins.

- Lobbies
> Players will be able to create or join a lobby. When creating a lobby, players can adjust settings such as time between
> zone changes and select the area to be played in from previously saved maps or the Map Editor. When joining a lobby, players 
> can select roles and will download the map.

- Map Editor.
> Using a map embed players can select an area to play in e.g a park. The selected area will be converted to an image 
> and the player will be able to outline the sections for the game. This image will be saved for potential future 
> games and will be shareable to other players when playing.

- Player Position with GPS
> Using the players GPS and the map embed, the players position will be displayable on the map. This will allow the player to
> see what section they are in and allow the players on the "it" team to see players who haven't been caught if they are in a
> closed section.

- Online \ Offline Mode
> Depending on where the game will take place, internet connection is not guaranteed. An Online and Offline mode will be implemented
> with important differences. In the Offline mode the position of other players will not be displayable and the person who begins
> as "it" will be able to predefine the order in which zones will close. The other players will have this information but only those
> who are "it" will have access to the order in which zones that are still open will close before the zones closing times.

- P2P connection - Strech goal
> For the offline mode a Peer to Peer connection system will be available although this just a strech goal.

### Background

> Where did the ideas come from?

### Achievements

> What functions will the project provide? Who will the users be?

### Justification

> Why/when/where/how will it be useful?

### Programming language(s)

> List the proposed language(s) to be used.

### Programming tools / Tech stack

> Describe the compiler, database, web server, etc., and any other software tools you plan to use.

### Hardware

> Describe any non-standard hardware components which will be required.

### Learning Challenges

> List the main new things (technologies, languages, tools, etc) that you will have to learn.

### Breakdown of work

> Clearly identify who will undertake which parts of the project.
>
> It must be clear from the explanation of this breakdown of work both that each student is responsible for
> separate, clearly-defined tasks, and that those responsibilities substantially cover all of the work required
> for the project.

#### Student 1

> *Student 1 should complete this section.*

#### Student 2

> *Student 2 should complete this section.*

### Risk Register

> You are to complete a risk register to demonstrate how you will account for the potential risks (i.e. something going wrong) when youa re working on your proiject. 
> The purpose of a risk register is to identify potential issues beforehand and plan mitigation strategies to ensure the success of the project. 
> The reisks are different for each project by some examples include 

> if you are using physical components (e..g sensors), what happens if they never arrive, or if they break, or if they are not suitable?
> if you are creating an AI/ML method , what happens if there is no suitable training data, or if the model performs poorly after training? 

| Description | Likelyhood | Severity | Mitigation |
|-------------|------------|----------|------------|
|             |            |          |            |
|             |            |          |            |
|             |            |          |            |


## Example

> Example: Here's how you can include images in markdown documents...

<!-- Basically, just use HTML! -->

<p align="center">
  <img src="./res/cat.png" width="300px">
</p>

