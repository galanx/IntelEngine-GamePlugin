# Changelog

## 4.0.0 — unreleased

The living world, by Galanx. People you know get on with their lives while you are away, ask things of you that the journal keeps, and come back to what is still open between you. Six new settings under "Living world" decide how much of it you get; at "Classic" everything stays as it was in 3.8.

### No stutter
Nothing IntelEngine does takes more than about half a millisecond of one frame of play any more (measured on the test profile, every round logged):
- Measured again on a list of some 1,500 plugins and 9,800 actors in memory. Three things were over and are mended: the search for a battlefield (1.5 to 1.7 ms in one frame, now at most 0.22 ms a frame over six), reading what stands between each person of a story and you (1.7 ms, now 0.3: the game was asked for a plugin by name four times a person), and gathering who serves you (0.75 ms, now 0.5). One is still over on such a list and is a single frame: making a soldier takes 1.0 to 1.4 ms, most of it the game's own making of an actor.
- Asking for a story no longer happens in one frame. Gathering the people, the places and the words for the writer took 0.74 to 0.85 ms of a frame in a small town and 2.4 ms on the large list; it is now done a part a frame (five frames in the test town, at most 0.32 ms of any one), and never in the frame of the look that decided to ask.
- The log is written by a thread of its own. Every line used to be written and flushed to disk on the thread that logged it, the game's own included; a director round alone logs some forty lines.
- The director's look at everyone loaded, and the one for scenes between NPCs, are spread over several frames, at most half a millisecond of each. In one frame they took 2.5 ms and 2 ms on a small load order, and more the more people a load order puts in a town.
- Item names are read once at the main menu. Asking someone for an item used to read every item name of the load order (11,000 on a small list), up to three times, inside one frame.
- The places a follower's own life can go are read at the main menu, not on the first look after a save loads.
- The story filters (block lists and white lists) are read on a worker thread before each round, not inside a frame every 30 seconds.
- The 12 decision calls of a director round go out in parallel off the game's thread; in tests all were back within 0.7 seconds.
- The look IntelEngine takes at each open story and quest every two seconds is timed where it runs. If one ever takes half a millisecond or more, IntelEngine.log says so at once, and the slowest of every 150 is logged, so a slow load order can be seen instead of guessed at. The first timing found two things that had been there all along, both mended: walking into a building with a story open asked of everything in the room who owns it (0.52 ms in the Bannered Mare; a look is now at most 0.08 ms), and the look at who follows you went through every actor of the game at once every ten seconds (now a slice at a time; at most 0.26 ms).

### The living world
- "How alive the world is": Classic (as before 4.0), Rumors (the world moves on and you hear about it), Lives (the default: followers you left behind also live lives of their own).
- Moments wait for a good time: arriving in a town or an inn, coming home, coming out of a dungeon, waking up. Loading a save is not an arrival. "How often something happens" sets about one notable moment every two game days (Calm), every game day (Normal) or twice a game day (Lively). The old clock is still there as a fallback and is paced the same way.
- "Interruptions at bad moments": whether someone may turn up during a fight, a conversation, a scene or a menu (Never, If urgent, Realistic).
- "Quest NPCs may move": whether people in a quest you are on may travel for a story (Never, If important, Freely). Only a quest with an objective in your journal counts, so the many quests that run from the start of a game no longer hold their people. The target of an objective you have open never moves.
- Road encounters no longer appear in plain view: the traveller is placed while unseen, farther spots are tried first, and the last resort is behind you.
- A destination with "river", "lake" or "bath" in its name ("White River Watch", "Riverwood", "Lakeview Manor") no longer sends the NPC to the nearest water: a real place name is matched first.
- The NPC social engine no longer sends someone away who is waiting by the road for you on a quest, and the hourly sweep of stray packages leaves them alone.
- Someone IntelEngine escorts somewhere no longer goes back to following you afterwards because of a SeverActions follow started in an earlier conversation: the escort ends it (a follower of your roster is never touched).

### How the director chooses
- Each candidate is judged on their own, from their own memories only: how strong a reason of their own they have to act now, and which kind of moment fits. Then the code picks one, and the dungeon master writes that one moment. Without a real reason nobody comes. With SkyrimNet's decision model set up, the judging runs there; otherwise the dialogue model does it. At Classic the single prompt of 3.8 decides, as before.
- After a game day and a half without a moment, a smaller reason may bring a gentle one (a visit, a word passed on, a message). Nobody is at the centre of two moments within two game days unless it is pressing, and someone chosen whose moment never went out rests for half a game day instead of being asked about again on every round.
- Candidates are ranked by your bond with them, how long you have been apart, who has been left out lately, and whether they are in your hold.
- Ordinary people right where you are (in a town, a settlement or an inn) can ask for help in public: they cry out to everyone around, then come over with the offer.
- The random encounters are drawn from the people of the hold you are in, at most one stranger from elsewhere. Before, the same three were taken every time (the orcs of Largashbur while you were in Whiterun).
- Someone held by a scene (a bard performing) is not sent anywhere until it ends.

### Unfinished business
- What someone asks of you is kept in the journal under Miscellaneous, "Unfinished Business", with its own objective and marker: a meeting, or a request (find someone, bring an item, take them somewhere, speak with someone for them). At most six are open, never two from the same person.
- NPCs ask in conversation (the new action AskPlayerForHelp) and you can turn them down (PlayerTurnsDownRequest). The watch sees when it is done: you found them, the item is in your pack, you spoke with them, you arrived together, you came back. Done, they pay what they offered, the item changes hands, and they remember it. Refused, never done or too late, they remember that too.
- A request can change course in conversation: the one who asked can call it off, give you two more days, need it sooner, offer more gold (at most three times the offer) or want another person, item or place. The journal follows. The one it was about can send an answer back through you, or come along to see the one who asked.
- The reward is fixed when the request is made, and the one who asked knows the sum, the time left, and afterwards that it was paid and is settled.
- How a request ended is heard of in the asker's hold ("Hulda asked Prisoner to bring her Ale, and Prisoner refused."), found when the talk turns to it.
- A meeting arranged in conversation is a journal entry with a marker on the spot until the waiting time is over.
- Items are found by name across load orders and languages: sorting tags ("[Drink] Nord Mead", "Drink - Ale"), words turned round ("Ingot - Iron"), and the plainest item of a vaguer word ("Mead") all match; part of a word never does.

### Quests decided by the world
Real quests now come to you: a title of their own in the journal under Quests, a description that grows as you go, an objective and a marker for each step, and a place in Completed Quests at the end. Every step is something the game checks for itself, never something said, so a quest runs the same in any language and with any dialogue model, and nobody can talk their way past a step ("hands over the ring" in a reply moves nothing).
- **A stolen keepsake**: someone's ring or necklace was stolen and the thief ran for a camp or a ruin nearby. Search the place, take it back (the thief may be waiting with his gang, or lie dead there already, killed by what lives in the place), and give it back. The item carries its owner's name ("Uthgerd's Silver Ruby Ring"), and only that one counts.
- **A brigand to deal with** ("Bounty: Torunn Grey-Cloak"): a named brigand and a gang have settled near someone you know. They are dead when they are dead, whoever killed them; then tell the one who asked.
- **A venture with a former follower**: a follower you left behind, living a life of their own, is met on the road on the way to a dungeon of your hold, alone or with someone they fell in with: another former follower, or a follower type you never travelled with (a hireling, an adventurer of your load order). They rest by the road ahead of you, the way you are going, or you find them at the dungeon; they recognise you and come over. Both have their say (an old friend glad to see you, a stranger meeting you for the first time). Coming along happens in the talk: ask to join and they take you along; when they ask you, a popup lets you answer once they have finished speaking. They follow you there as your companions (through SeverActions when it is installed, otherwise SkyrimNet's follow), clear it with you, and split the spoils; afterwards they walk home. Turn them down and they answer and go alone, and remember it. Both remember how they came to travel together.
- The marker of a step is checked every look and moves when what it stood on is no longer there (the holder of the item, else the foe, else the heart of the place).
- The one who asks comes to you, says it in their own words, and you answer in a choice popup: take it on or not. Handing something over is a choice popup too, once they have spoken to you and the item is in your pack.
- What the asker knows is what is true: what they asked, what they offered, and whether it is done. A claim in conversation that it is done, when it is not, does not get you paid (seen in a test: "Word of a death like that reaches me at once, and none has").
- Every ending is remembered and talked about: done and paid, refused, never done, or the item found and kept. The people of the hold hear of the trouble while it lasts and of how it ended.
- At most three quests are open at once, never two from the same person, and someone whose quest just ended does not ask again for a week. The kind of quest changes from one to the next. When no quest fits the person the director chose (no place nearby, already busy), what may still come is a rescue, told as a story of the town, or one of the factions' own quests; the old "clear out" and "find an item" quests of 3.8 are not written in their place (at Classic they come as before). Nobody in a quest is moved by the lives of followers.

### Stories of the town
Stories of several steps among the people of a town, with real clues in real pockets and homes, and branches that follow what you find, what you say and what you choose (docs/STORY_ARCS.md in the native plugin). Each has its own journal entry under Quests, with an objective and a marker for every step.
- **A trail to follow.** A hunt had one body to look at, by the lair's own door. Now it has a trail: up to three things to examine, laid along the way to the place, the farthest first: a beast it took, another, then the victim. The journal shows the way to the first only. Each window tells what you see and which way the trail leads on ("The trail leads on to the west."), and the next is found by walking it (it is marked after a game hour all the same, so nobody is left standing in the dark). Every clue shows something the others do not, and only together do they tell what did it. The signs lie between you and the place, where someone coming would pass them, never in sight when they are laid, and only on open ground (the game's own collision is asked: the ground mesh runs under overhangs). Played on foot: a bait goat at 4,400 units, the horse at 2,200, Torvald by the cave, each seen, examined and pointing on; laying a sign cost 0.22 to 0.37 ms of one frame.
- **What a story leaves to the next.** The writer of a new story was shown an earlier story's title and premise, never how it ended or what you chose, so a later story could not build on it. Now every ending says what it leaves unsettled ("Sigurd went free and still owes Belethor"), the writer is shown how each earlier story ended in your journal's own words, and an open end comes due: two game days later at the earliest, the next story of that town grows out of it, with the same people where they fit, once, and never two such stories running. Played: after a hunt in which Elrindir's part was kept from his brother, the next story of Whiterun was "The Hunter's Widow": Elrindir, pale, with anonymous notes that have a goat's head scratched on them.
- **Tales written for the town**: the dungeon master writes each story for the people actually there, not from a fixed list: a hidden truth, each person's own secrets and wants, and steps of every kind (talk, search a home or a pocket, hand something over, a decision, someone coming to see you, a day's wait, a fistfight, going to someone's house). Every likely way a talk can go is prepared in advance; when you have talked with someone and the conversation goes quiet, a small call reads what was actually said and the story takes the branch it came to (a confession, a denial, a bargain). Endings change things that last: people become friends or rivals, someone leaves town for a while or is taken by the guard, gold changes hands, and everyone remembers it in their own words.
- People are cast by who they are in the game: their work, their temperament (someone who never breaks the law never steals; a coward never fights; an innkeeper never brawls), their home, and the ties the game gives them (family, friends, rivals such as the Battle-Borns and the Gray-Manes). Someone a quest of yours still needs keeps their own story: the dungeon master is told their quest and never touches it; the quests in your journal are never contradicted.
- No story cuts into a quest you are in the middle of: for a quarter of an hour after a quest of your journal moves on, the town's stories wait. They come when you idle in a town, a day apart; what was told is never told again (a later story may pick up a thread an earlier one left open).
- Every story is checked before it begins: every person, item, step and branch must be something the game can carry out, and every path must reach an ending; a story that does not hold is sent back once, and without a model the old stories below are told instead.
- The person you are talking with about a story stays with you while you talk, and goes back to their day once the talk has been quiet for a minute or you walk away. Jon Battle-Born used to walk home in the middle of being asked about a goblet.
- The journal shows the story's own words: its title, each step as an objective, the story so far, and at the end the whole chronicle with how it ended.
- **Someone taken**: a story may now be about a person of the town who is held at a place nearby: a bandit camp, a Forsworn camp, a necromancers' or vampires' lair, a hagraven's nest, a Falmer hive. They are taken where nobody sees it, before the one who asks reaches you. They are not in the game again until you have come as far as the heart of that place; there they kneel bound, the people of the place leave them be (the game's own rule for a dungeon's prisoners), and they cannot die. You free them with your own hand: walk up to them, the crosshair says "Cut loose", and your activate key cuts the bonds (coming near is not enough, so nobody is freed by a player sneaking past or with the captors still standing around unless the player means it). They walk out with you, tell you what really happened once you ask, part from you under the open sky and walk home. A story turned down or left to lapse brings them home unseen, with no memory of anything that did not happen. Played in the test game from offer to ending with a story the dungeon master wrote (a wife who walked into a bandit camp to buy her husband time).
- **A rescue is for someone who is theirs**: the one held is close to the one who asks, as the game itself has it (kin, a spouse, a friend, the same roof), or no rescue is written for them.
- **A talk never hangs**: when you have really talked a matter through with someone and what they said fits none of the ways the story had prepared, the nearest is taken after the third exchange, instead of the journal standing still.
- **The journal's marker keeps up with you**: where a step's marker points is worked out afresh every two seconds from what is true in the game at that moment, for every kind of step, and it is never left on something that is not there. "Go to their house" and "search their house" lead to the door of the house, not to the owner wherever in town they happen to be. Someone who is not in the game just now is marked by their home.
- **Things done out of order count**: a story no longer assumes you take its steps in the order it was written. If you had been down to the heart of a place before the journal sent you there, that step is done the moment the story comes to it. If you find someone held and cut them loose before you ever asked around about them, they are free from that moment, the steps that would have led you to them drop out of the journal as things that never happened, and the story goes on from the rescue.
- **Something walks by night**: a new kind of story, a haunting. Out by one of the places near town the shade of someone who died there is seen after dark, and somebody in town knows why it does not rest. It is there only between nightfall and first light. You can speak with it like with anyone, and it answers from what it knew in life ("An elf with a bow left me on these rocks. He took my mother's necklace. Find it, and I may rest."). It harms nobody who leaves it be. You can strike it down, which ends the fear and buries the truth with it, or find the one thing it wants among the living and hold it out: the crosshair then reads "Lay to rest", it says its last words and is gone. If you go there on the first night, before asking anyone, it is already walking. Never two such stories running.
- **Something is killing people**: a new kind of story, a hunt. Someone wants to know what killed a man or their beasts out by one of the places near town. You ask those who saw something (and they may be wrong); you find what was left of a victim lying outside the place and look at it closely (the crosshair says "Examine"; a window tells you what you see); and what you see is true of what lives in that place, because the dungeon master is given each place's own signs and must take the clue from them: two small wounds and a bloodless body where vampires den, plain steel and a missing purse where bandits camp. Then you face it, and what you learned out there overturns something that was said in town. You can come on the remains before anyone asked you to; what you saw still counts.
- **Saying what did it**: in a hunt, someone may ask you what you think killed the victim once you have looked: the truth stands among what the guard says and what others would rather believe. Name it rightly and they give you what they have against it (Cure Disease where vampires den, a scroll of fire against a troll); name it wrongly and you go without, nothing worse. The dead carry the name the story gives them.
- **Not the same cave again**: a place a story led you to rests for the next few stories, as long as the town has others to choose from. When a story does lead back to a place you once cleared, it has a new master, and some of its kind have moved in with it.
- **The journal no longer repeats itself**: each time a story's marker moved, or something of the story was put in the world, the current objective came up on the screen again. The marker now moves without a word.
- A place's master killed before the story asked for it counts when the story gets there, also after a save and a load.
- **Rescues are stories now**: the rescue quest of 3.8 is gone at the new levels of the living world. When the dungeon master wants a rescue, a story about someone held is written instead, with everything above. The old rescue teleported the victim in view, beat them into bleedout, and could leave a hostage nobody could find or a place nobody could enter. The old "clear out" and "find an item" quests are no longer written either where the engine's own quests exist; at the Classic level, where the old ones still run, a dragon is never placed indoors, a rescue no longer leaves memories of a captivity that never happened, and a quest whose enemies could not be placed completes on reaching the place instead of never.
- **Never an errand**: a story the dungeon master writes is refused unless its ways end differently, and a place out in the world is one act among people, never the whole of it: at least two steps among people besides the place, and after the last step out there a talk or a choice that what you found forces. "Go there, kill it, bring it back" is no longer accepted as a story. After two stories in town the next one leads out into the world, by the engine's count.
- **Out into the world, mended**: played on foot into a bandit cave and a Dwemer ruin. What you are to take from a place's master is marked on the body, wherever the fight ended, not on the empty room. A town's working mine is no longer mistaken for a bandit hideout. And places whose heart only exists in the game once you are inside (most Dwemer ruins) now work: the journal leads you to the place, the master waits at its heart when you get that far, and the marker moves onto it; before, such a story could not be finished.
- **Out into the world**: a story may lead out of town, into a ruin, a tomb, a camp or a den of the same hold for what was lost there or after whoever wronged someone. What waits at the heart of the place is of the place's own kind (a bandit chief in a hideout, a draugr in a tomb), carries the story's name, and may carry the thing the story turns on. Places a quest of the game or of your journal still needs are never used.
- **Someone with a reason of their own**: when the dungeon master finds that someone has a real reason to seek you out (unfinished business, a debt, news, trouble only you can help with), their story is written around that very reason and they come to you, at home too.
- **How far a reason carries**: nobody visits from across the world for a small thing any more, and no setting can loosen this. Someone in the place you are in acts on a real reason. Someone elsewhere in the same hold comes only on a pressing matter, or on a real one if they are close to you (once travelled with you, a confidant, wed to you). From another hold only someone close to you comes, and only on a pressing matter (anyone else only when it is urgent beyond doubt), never to waylay or shadow you, and never twice within ten days. Such a traveller is on the road for eight hours before they reach you, and your own hold-restriction setting is asked before their story is even written. Whoever does not qualify simply does not come: their reason keeps until you are next their way. Inside a story the same holds: a visitor or a shadow does not follow you into another hold; that step waits until you are back.
- **At a walk, and not across the world**: someone who brings you their trouble walks over; only those who have truly been looking for you (someone close to you, someone who travelled from another hold) hurry, and only attackers run at you. If you leave before they reach you they let it be and go back to their day; their story keeps for a few days and they bring it the next time the two of you are in the same place. Nobody is set down beside you in another town any more.
- **Strangers stay strangers**: people who have met you, or whose town has heard of you, come first. Someone who knows nothing of you only speaks to you when you happen to be right there, and says so: a stranger taking a chance on a stranger. Having met you means the two of you have talked, more than a greeting, or travelled together, or you took on a story of theirs before.
- **Nobody leaves town, or their post, to find you**: an innkeeper stays at her counter, a merchant at his stall, a guard on his round, and nobody walks out to the farms after you. Their trouble goes round as talk in town with where to find them, and they speak up when you come by. Someone who knows you and only held back because you were out of town comes over once you are back among its houses.
- **They take their leave**: once you have answered, the one who asked says their word to it and walks back where they came from, instead of standing at your side for minutes. Keep talking to them and they stay as long as the talk lasts. Back at their spot they go on with their day at once (they used to stand rooted there for up to a game hour).
- **A quiet stretch**: after any story has come to you or ended, nobody brings a new one for six game hours, whatever their reason.
- **Not in front of the people it is about**: nobody brings you a matter while someone it concerns is within hearing of you. They hold back, or turn round on the way, and come when the two of you are apart. Hearing is SkyrimNet's own interaction distance (1600 units unless you changed it), because whoever is within it really does hear the line and may answer it.
- **The reward is handed over in person**: when a story ends somewhere away from the one who asked, the journal sends you back to them ("Tell Faendal how it ended"), and they pay when they have heard it from you. Gold no longer appears in your purse from someone on the other side of town. If you never go back within three days, or they die first, the story ends as it did, unpaid.
- The dungeon master is told to write what each person did in plain words. A vague secret ("what I did") made the person speaking fill it in with the game's own quest.
- **Never the game's own quests again**: the dungeon master is told which quests and errands of the game each person has a part in and where you stand in them. A story never retells one (no second letter between Faendal, Sven and Camilla), keeps clear of those you have not finished, and may grow out of how a finished one ended.
- A request or an answer too long for its box now ends where a sentence or clause ends, instead of breaking off in the middle.
- **A no is not for ever**: someone you turned down is still never the subject of a courtship story while that stands, and nobody ever presses you. But a season later (thirty game days), and only if the two of you have since grown closer than you were then, a story may bring you together for a day and leave you room, once, to show that something has changed. Every other way through it ends as a good day between friends.
- **Stories of the heart**: when something has begun between you and someone, a story may be about the two of you instead of a favour for a third person: a courtship while it is still unsaid, the life you share once you are lovers, betrothed or wed, the household when a child is coming or there are children. What is true between you is read from the game and from the mods that keep it (SkyrimNet Relationships, the game's own marriage, Fertility Mode through SeverActions, Kinship), all optional; without any of them, someone the game lets you marry who is already your friend can begin one while you wear an Amulet of Mara, the game's own sign that you are looking. Where you come closer the bond the game keeps grows a step; where you were careless with them it cools; you can always say no kindly. Never two such stories running. Never with a child or anyone who looks or sounds like one, never with your own family, never with someone you turned down. Told in words only; the story ends at the door. A story about someone married to another only comes where OStim is installed and you have already welcomed them. Nobody pays gold for a story like this, and a kind no cools nothing between you. Played once in the test game (a courtship in Whiterun).
- The dungeon master is told what stands between you and each person of a story, so nobody writes your wife another love.
- **Without a relationship mod, how people stand with you is read from what passed between you.** Once somebody has spoken to you a few times, the model reads what they remember of you and your last talk together and says where the two of you stand: a stranger still, an acquaintance, a friend, a confidant, lovers, or someone who has turned cold or hostile; whether they have shown they are drawn to you; and whether you welcomed that or turned it down. It chooses among named answers, so it works in any language. One reading is not taken on its word: it has to be sure, or say the same twice. A no from you stands until you plainly take it back. This is what lets a friendship that grew in talk count: such a person may come to you from farther off, a courtship story can begin with them, and someone who has soured on you no longer brings you their troubles. Never read for children.
- **A shy admirer.** Until now a courtship story had one shape: the one who is drawn to you comes and says so. Now, when someone of the town who would ask you for something is close to a person who is drawn to you (kin, a friend, the same roof), you have not answered them either way, and they are no bold person by the game's own measure, the story may be theirs: the one close to them comes in their stead, with a word or a small thing and no name, or because they cannot watch it any longer. The story is you finding out who it is, and what you do about it: you can welcome it, say no kindly, or let them keep their secret, and only cruelty cools anything. Once for each admirer, never a child, never kin, never someone wed, nothing explicit. Played: the innkeeper spoke for her barmaid ("Would you hear me out about a girl of mine who cannot say what she means?"), a neighbour half-knew, the barmaid watched from a distance before the two stood face to face; the innkeeper held her offer back while the girl was within earshot.
- **Stories know what the town is talking about and what times these are.** The author of a town's story is now told the talk going round the hold (a deed of yours, news of a battle, what became of someone you travelled with) and the state of the wars with your name in them (a rank you hold, a faction that thinks well of you or holds you for an enemy). A story may grow out of either, where one of its people is honestly part of it; it never moves an army or decides a war. Played: with the Legion and the Stormcloaks at war, a story of a merchant's missing casks turned out to be a townsman quietly selling to the Legion's quartermaster. Stories of the heart are told neither: they are between two people.
- **Beside SkyrimNet Relationships, each person is spoken for by whoever knows them.** That mod keeps the people it watches (your followers, and whom you enrol) far better than a reading can, so for them its word counts and nothing is read; new is that its ill will counts too: someone it holds as disliked, resentful or an enemy no longer brings you their troubles and is no friend in a story. Everybody it does not watch (the innkeeper you drink with, the smith you trade with every week) is read as above, for friendship and ill will only: nothing of the heart is ever read while that mod is installed, a courtship is its to begin. And when it takes on someone you have known for a month, it starts them as a stranger: what was read before stays underneath, as friendship or as a grudge, until its own tier has caught up, so nobody forgets you overnight.
- **Waylaid on the road**: someone in a story with something to hide and the means may pay men to stop you. They wait on the road itself, out of sight, or come up behind you; never in a town, never in the middle of another fight or a quest of the game. Their leader comes up to you and has his say first. Then it is yours to answer: fight them; talk to him (buy them off, turn them, get him to name who paid; the talk itself is read, and they leave when it is settled); or lose, which is not the end: you are beaten to your knees, they take what they came for and go, and the story goes on from that loss. How many come is fitted to you (one man for someone new to the road). What the leader carries stays on his body, marked in your journal.
- **Followed**: someone in a story who has a reason not to come openly (too ashamed, too afraid, or sent to watch) may shadow you out of doors, from behind, crouching and holding back when you stop. Turn on them, or wait: after a while they gather their courage, stand up and walk over, and what they have to say is the story's next turn.
- **Old companions**: a follower you parted with and who went on to a life of their own may have a part in a story when there is a real place for them: the journal leads you to them wherever that life has taken them (a camp, a ruin, another town), or they come and find you. They stay where the story has them until it is over.
- Whoever holds office in a hold (a jarl, a steward) may have a matter brought before them in a story, and may judge it; a story never makes them the guilty one.
- **Never the same story twice running**: the engine itself holds back what was told lately. After a story with an ambush or someone shadowing you the next three have none; a brawl is not followed by another; after two stories that led out into the world the next stays among people. The writer is not even shown what is held back.
- **A thief among us**: someone's ring was stolen from their home. A neighbour saw who slipped out that night, and tells you if you ask. The ring is hidden in the thief's home once you go in (it is yours to take back, no theft); then confront the thief: hand them to the guard (taken away while nobody watches, let out two days later) or let them go. Return it and be paid. Find it before you ask the witness and you go straight to the thief; give it back without any confrontation and the thief gets away with it.
- **Bad blood**: two neighbours at odds over something real (a debt, gossip at the inn, an insult, a game of dice), each telling it their own way. Hear the other side, then settle it with your fists (the game's own brawl, or a brawl of SeverActions when the rival takes up the challenge in talk), talk them round (it takes some Speech), pay them off, or stay out of it.
- **Murder in town**: someone of the town is found dead at home. See where it happened, question the one who saw the killer hurrying away, find proof (the bloodied dagger hidden at the killer's home, the victim's gem still in the killer's pocket) and name the killer. Three suspects; name an innocent and they are shamed before the town while the killer walks free.
- **Flavours mix**: every story has a main lean (sixteen of them now, the uncanny and a hunt among them) and a second thread to weave in, so a hunt can also be about two brothers' quarrel, a debt or a family's honour. Played: "What the Antlers Hid" (a hunt and a family secret), "The Hunter's Silence" (a hunt, and what the Battle-Borns would rather bury).
- **Told another way each time**: three stories written one after another on a new game were the same story (someone of the wilds with a hold over a townsperson, a camp to clear, a chief to kill, and titles that began alike: "The Quiet Order", "The Quiet Husband", "The Quiet Ledger"). The engine now holds to more than it did: the master of a place is never killed in two stories running; the next story that leads out into the world goes to another kind of place than the last (not a second bandit camp while a ruin, a den or a barrow is near); a new title shares no word of five letters or more with the titles of the last six stories (the writer is told which word, and asked again); and the reward is no longer the same sum every time. The writer is told that trouble mostly comes from among a story's own people, and what the town says first is what was seen or heard of the one in trouble, not that they "want someone discreet". Played: after "The Quiet Husband" (a debt, a camp, a chief) came "The Mare's Second Ledger", a quarrel over who is to have the Bannered Mare one day, told wholly among people.
- **A decision you have already spoken is not asked again.** A decision step put its window up as soon as you had exchanged a word with the person, even when that word was the decision ("Ulfberth, your wife is faithful. She has been hiding a debt..." was answered in full, and then the window asked what to tell Ulfberth). The talk is now read first, once both have gone quiet: what you plainly said is taken as your answer, and the window opens only when you have not decided anything yet. An answer that needs your Speech always asks by window.
- **Whoever comes with a story waits their turn.** Someone who reached you while you were talking with somebody else made their request into that talk, and SkyrimNet gave the line to the person who was speaking (an acolyte's plea came out as an aside of the smith's, seconds after the smith's own story had ended). Now nobody sets out toward you with a story while you are in talk with someone else; one who arrives during a talk stands by until it is over (the other's line said, and a moment for you to answer) and then speaks for themselves; and one who arrives just as another story has come to you or ended lets it be and comes another time.
- A quest the game moves on behind your back no longer holds the town's stories back. Any quest of a journal type that changed stage counted as "the player is on a quest" for a quarter of an hour, and the game does that all day without you (four quests of the Companions within three minutes of loading a save). Only a quest your journal shows counts now. On a large mod list the town's stories might never have begun.
- A reader of a talk goes by the person's own lines. A talk step was once read as "she confesses" on the strength of what you had just said to her, half a minute before she spoke.
- A choice window no longer opens over a menu or SkyrimNet's chat box: whatever was being typed there would have answered it.
- The game's own errands that carry no title (Amren's family sword is one) are known to the writer by what they ask of you, and no story is made of such an errand or of the thing it turns on. The first story written for Whiterun on the play session was about that sword.
- When a story's asker does not come after all and the writer wrote no talk for the town, the town now passes on the asker's own request ("has been asking people for help, in words like these: ...") instead of "has trouble, and has been asking around".
- Out in open country, where the game names no place, you are in the hold you last walked in. There your hold used to read as none: everybody of the hold counted as living in another one, and your own limits on who may cross holds counted as passed.
- The town's stories come by themselves: when you have spent a couple of hours in a town, at least a day after the last story began, someone of that town may come to you with one. The kind changes from one to the next, at most two are open at once, and whoever asked does not come with another story or quest for a week.
- Everyone in a story knows their part and nothing more: the thief denies it, the witness tells what they saw, a suspect has an alibi. Words move nothing: a step is done when the game says so (the ring in your pack, the brawl won, your answer in a popup). Paying with their own action, or taking the ring with their own action in talk, is counted, so nobody pays twice and nothing gets stuck.
- Endings are remembered by those involved and talked about in the hold. What the hold heard of a story that happened after the save you load is withdrawn after the load, for stories, quests and lives alike.
- Nobody a quest still needs, nobody essential, no child, no jarl, steward, merchant, innkeeper, bard, guard or follower is ever made a thief to be jailed or a victim; nobody old is drawn into a fistfight.

### Any language
The mod was written in English and in many places only understood English: a time ("tomorrow morning"), "home", the word "none", a name exactly as the game spells it. In a game of another language, or an English game whose people speak another language, schedules were never made, "home" was looked up as a place, and "Lydian" was nobody.
- **Names as people say them.** Russian declines a name ("к Лидии" for Лидия, "в Вайтране" for Вайтран), German puts an article and an ending on it ("zur Beflaggten Mähre"), Albanian hangs the article behind ("Whiterunit", "Lydian", "Huldës"), Korean and Japanese hang a particle behind without a space and write a name's words with a dot or with nothing between them. People and places are now found in all these forms, by structure alone (what separates words in any script; one word beginning with the other and only a short ending differing; little words beside the name let go), and still never one name for another ("Anna" is not "Annekke", "Edan" is not "Edan's Shadow"). A slip of the pen is counted in letters, not bytes: a Korean name of three letters used to get the allowance of nine.
- **Language packs.** What the mod has to know about a language is in a file, `SKSE/Plugins/IntelEngine/languages/<name>.tsv`: its words of time, its words for home, outside, upstairs and the like, its words for "none", and the little words beside a name. Ten ship: Russian, German, French, Spanish, Italian, Polish, Japanese, Korean, Chinese (both writings) and Albanian (standard and Gheg). "завтра утром", "morgen früh", "nesër në mëngjes", "明日の朝", "내일 아침", "下午6点" are read as the times they are; "домой", "nach Hause", "n'shpi", "家" are home; a house's name that holds the word for house stays a name. Adding a language is adding a file.
- **Which language.** The language you read in is told by the game's own setting and, where that says English, by the script the game's place names are written in (Korean and other translations the game never shipped run with the setting left at English). The languages people speak are read from SkyrimNet's translator settings, so an English game whose people speak Albanian is understood as that: the journal stays English, and what they say in Albanian is read. Two settings, "Language of journal and messages" and "Languages people speak", both "auto", on SkyrimNet's page and the dashboard.
- **What you read can be translated.** Every notice, button and battle line goes through the pack of your language: a pack's line `label <TAB> {1} headed off to {2} <TAB> ...` is found under the names and filled with them. `languages/_labels_template.tsv` lists all 160 sentences for translators (generated from the sources, and a check keeps it complete). No pack ships translated sentences yet: until one does, they read English. The writer of a town's stories is told your language and writes the journal, the choices and the clues in it.
- **Lengths in letters.** A text's limit was counted in bytes: a Russian journal line lost half of what it was allowed, a Japanese one two thirds, and both were cut again at the first save. Limits are letters now, a cut ends at a sentence end of the text's own script ("。" too), and the save keeps the whole.
- **Politics without English names.** Whether you are in a faction's hold was decided by comparing an English name from the data file with the hold's name as the game shows it; in a translated game they never matched. It goes by the game's own records now. A faction's leaders are also given as the game names them, so a leader knows themself in a translated game. And a hold's name is found as whole words: "reach" used to be found inside "Dragonsreach", which made the jarl's hall part of the Reach.
- The older dungeon master rejected every person it chose in a Russian game (names were lower-cased two different ways); a rumor is no longer thrown away because it names its subject in another case ("Лидию", "Svens", "Sinmir's"); "none" in any language in force is none; a list of companions may use the commas of other scripts.
- Played in an English game with six spoken languages switched on: the times, places and names above, through the real actions' readers. Not played: a game actually in another language, and whether the text encoding of German, French, Italian and Spanish game files needs converting (they may not be UTF-8); Japanese, Korean and Chinese in the journal and popups need a font that has the letters.

### The talk of the day
Rumors used to be a line a hold remembered for ever and mentioned only when a conversation happened to turn to it. Now there is talk that moves:
- **It travels.** What happens is talked of in its hold, and the more it matters the farther it goes: small things never leave the hold, bigger ones cross a border a day along the roads, the biggest are heard of in every hold. Where it only arrived by road people say so ("so say travellers come from Whiterun; nobody here saw it").
- **It fades.** Trouble is talked of for a few days, a deed for a week or two, then nobody mentions it any more. The hold's long memory of what you did is kept as before.
- **Someone tells it.** Innkeepers, their servers, bards and merchants hear everything (by the game's own job factions, so any mod's innkeeper counts): ask one for news and they pass on what fits, one thing at a time, as hearsay. Everyone else knows the one thing the whole town is talking about.
- **It is brought up when you walk in.** Arrive at an inn and whoever keeps it may tell you the one thing most worth a word, in their own words, once in a while and never twice the same. They remember having told you.
- **A rumor can be the start of a story.** A stranger elsewhere in town with trouble used to have no story at all. Now their trouble becomes talk in town first, with where to find them. Go there, or simply pass by: they speak when the moment is right, and at once if you walk up and ask.
- **They still come to you, and you see them asking.** Talk in town makes it rarer and less about you; it does not replace it. A stranger who is right there still comes straight up. Of those whose trouble is talk, about half stop whoever stands near and ask them first when you pass by ("Mistress Avenicci, pardon the stop... do you know anyone who'd look into who killed him?"), and about one in three, when the talk has gone round for half a day and nobody came, set out through their own town by day, ask on the way, and reach you ("I've asked near every soul in this market and gotten nothing but shrugs. So I'll ask you plain"). The rest stay talk until you go to them or the talk dies down.
- What a story, a quest, a request or a former follower's life leaves behind all feeds the same talk. After loading an older save, talk that belongs to the abandoned timeline is withdrawn.

### Politics
- **Nothing against the game's own stories.** The Companions, the Thieves Guild, the College, the Dark Brotherhood, the Thalmor, the Silver-Bloods and the Black-Briars (and the Dawnguard and its vampires, if you add them) are bound while you have not finished their questline: no war by them or against them, no attempt on their leaders, nobody of them killed, seized or replaced, and they are never dissolved. They still trade, quarrel, brawl and make friends. Finish the questline and that faction is free. The log names the quest that binds each ("CompanionsFaction is bound by its own story in the game (Glory of the Dead)"). A faction a mod adds is free unless you say otherwise; `free_after` in factions.yaml (or the editor) sets the quests for any faction, and an empty list frees it.
- **Politics is heard.** What happens between the factions becomes talk: a war declared or ended reaches every hold within days, a battle the holds around it, trade and quarrels the hold they happened in. Innkeepers tell it, a battle that is coming is talked of before it is fought, and your part in one is in the telling.
- **The faction editor.** Dashboard, Politics, "Edit factions": add, change and remove factions without touching factions.yaml. It offers what your own load order has: search every faction of the game and of your mods by name, id or mod file, search every leveled list of people to raise soldiers from, add leaders by name; kind, seat, rivals and allies are buttons. A record without an editor id is written by plugin and form id, which `skyrim_faction_id` now accepts as `soldier_template` did. Saving keeps your old file as factions.yaml.bak, leaves the rest of the file (default relations, war_allowed, your comments outside the factions section) as it was, reads the new file back before it replaces anything, and takes effect at once.

### Battles
- **Fought on a field, not on you.** Armies gather near a named place first and the holds hear of it. Come near and they are drawn up on open ground away from you: two lines, a captain before each, on dry land, away from houses and people. Nobody appears at your feet, nothing is fought in a street or a tavern. Stay away and it is decided without you and told.
- **You are asked.** A captain calls to you in his own words; you stand with his side, with the other, or keep out of it. Soldiers strike more lightly and stand more than the game's own, so a battle lasts minutes: long enough to walk into, fight in and turn. Each army brings up its own reserves from behind its line, out of your sight.
- **What a battle may have in store.** A champion who comes up when the fighting has gone on a while (three times a soldier's hardiness, named for his army, worth 200 gold and a good deal of renown to whoever cuts him down); a second force hidden on the flank; men who turn their coats when their side loses heart, and are called turncoats from then on. Never all at once, never in a skirmish, and never shown beforehand: you see it when it happens.
- **A ladder to climb.** What you do for a faction earns renown with it, and renown a rank: Auxiliary, Sworn Sword, Veteran, Captain, Champion for an army (guilds and houses have their own names). A rank pays better after a battle won, puts two and later four soldiers at your side, and from Captain on the line waits for your word to charge. From the third rank your name is known beyond the faction, and people speak of you as that.
- **The call to the line.** When armies gather and you hold a rank with one of them, it sends for you: a journal entry, "Called to the Line", with the place marked. The journal says afterwards how it went. If you are already close by, you are called when the lines are drawn up and the marker is on your own captain.
- **A captain knows an enemy officer.** A commander does not invite somebody his army knows as an officer of the other one; he shouts at them instead. Going over to the other side remains your own choice.
- **Nobody stands about.** Reserves, a hidden force and anyone whose opponent has fallen go for the nearest enemy instead of gathering in a knot in the middle of the field. The soldiers at your side follow a few steps off instead of walking into you.
- **Afterwards.** One of your side comes over the way a companion follows, stops a few steps in front of you, says what he thinks of it and hands you your pay. If nobody of your side can bring it (none left standing, or no way to where you are), it is sent on and you are told: a battle won always pays. The beaten run and the winners walk off toward a town by the roads, their own if it is far enough; nobody stands about on the field. A soldier who gets caught on his way off (a fenced garden, a ledge) is sent another way, and if there is none he rests where he is. The battle, and your part in it, is told in the hold.
- **Big mod lists.** Played on a list of some 1,500 plugins with hair-and-cloth physics on every soldier. Soldiers and the dead are now taken out of the game only once they have left the loaded area: removing them while the game still held their bodies, far off and unseen, could crash it inside the physics mod. The search for a battlefield is spread over several frames.
- **A battle is no crime.** A stray blow in the press no longer turns your own line on you, and if it kills a comrade the hold's guards do not come for you in the middle of a battle: bounty that arises while you fight is struck out again (what you owed before stays owed). Your own side still remembers it: it costs renown and standing, and word goes round.
- **On the dashboard.** Politics shows what each faction knows you as, your rank and what the next one gives, battles being fought and armies gathering, and a chronicle of what happened. The new World page shows the talk of the day you have heard, the stories you have taken on, and your people.

### What 3.8 had that 4.0 had lost
Found by going through 3.8 feature by feature:
- A bounty, a keepsake hunt or a venture could be set at a place a quest of the game that you have not finished still needs. They keep clear of those now, and of a story's places, as the town's stories always did.
- Your block lists and white lists (names, factions) only held for the old dungeon master. They hold for the town's stories now: who asks and who has a part.
- The "Stories" switch did not stop the town's own stories. Off, none begins; one that is open goes on to its end.
- Someone far away who had word for you either travelled to you with a whole story or did nothing. They send a letter by courier again.
- **A faction that holds you for an enemy sends men after you again.** In 3.8 this was one of the dungeon master's choices; the new director judges people one by one, and a faction is nobody, so above "Classic" a patrol had no way to happen any more. It is decided in code now: at a standing of -40 or worse, a share of the moments the director would let land anyway becomes a patrol of that faction (one in five while the feud is young, every other one when it is deep), three to seven soldiers by how deep it is, never within two days of the last. It counts as a big moment, so you are left in peace afterwards as after any other. Everything else is as before: out of doors, away from towns and houses, from where you do not see them come. Played: Stormcloaks at -78 came after the test character on the tundra; on a mountainside with nowhere to come from unseen nothing happened and the dungeon master looked as usual.
- **Nobody is sent to where nobody could have followed you.** "npcs spawn in dangerous places to talk to me and they die / im in the soul carion / how did they even manage to get here" (a user). The new director had made visits from afar rare, but nothing said that a place cannot be reached at all: in the Soul Cairn everybody counted as "in another hold", and someone close to you with a pressing reason could still be sent and set down beside you. Now: in a place that lies in no hold and in no land one can walk or sail to (the Soul Cairn, Apocrypha, Sovngarde, a mod's island), nobody is sent and nobody already on the way is set down beside you, at every level and whatever the settings say; someone on your own errand waits until you are back. And above "Classic" nobody is sent into a dungeon after you: whoever has something for you waits until you are out (leaving a dungeon brings a look of its own). It holds for the director's pick, a town story's asker and its visitors, road meetings, a faction's patrol and a story's hired men. Whoever is already there with you may speak. Played: in the Soul Cairn an innkeeper's story waited as talk in her town, a forced patrol did not come, and a visitor dispatched by hand set out and let it be two seconds later; in Bleak Falls Barrow the same; back in Whiterun people came again.
- **Nobody in arms comes upon you in a private moment.** People complained of soldiers appearing in the middle of theirs. A faction's patrol, a skirmish of two factions near you, the hired men of a story and a killer after a leader you stand by now all ask the same question first, and stay away while: a scene with you is running (the game's own, or an intimacy mod's) or ended within ten minutes; somebody is talking with you or you spoke within the last two minutes (a SkyrimNet conversation has no menu of the game to tell it by); you sit, lie or sleep; you wear nothing (a bath, or more private than that); or you have stayed where you are for the last minute. They fall on a traveller: someone on the move, out of doors, away from towns and houses. Until now a skirmish near you asked only whether you were out of doors, and the others knew the game's own menus and a running scene but not a talk, a rest or the minutes after. Played: with a faction at -78 and every roll forced, nobody came while the test character stood still, wore nothing, or was being spoken to by a passing thief; walking the road, the patrol came.
- **The switches for each kind of moment hold inside a story too.** "Ambush", "Stalker", "Quest" and the quest kinds governed the dungeon master's one-off moments only: a story of the town could have an ambush or a shadow in it with those switched off. Now: no ambush step with "Ambush" off, nobody shadowing you with "Stalker" off, nobody held captive with "Rescue" off, no master of a place to kill and no bounty with "Clear out enemies" off, no keepsake hunt with "Find an item" off, and with "Quest" off no story of the town begins (nobody brings you their trouble).
- **Upgrading a save.** A save made on 3.7.1 was loaded with this version: it comes up at "Lives" with the default pace, not at "Classic" (a script comment in the mod claimed new settings read zero on old saves; they take their defaults).

### Followers you left behind
- At "Lives", a follower you dismissed starts a life of their own after a while (7 days by default; 30 for one you told to wait, once their follower mod lets them go): work at an inn of the hold, an adventure at a dungeon (now and then with another former follower), a trip to a town, home for a while.
- Each step happens only where you cannot see it. They remember it, people of the holds concerned may have heard of it, and their own prompt says where their life stands. When you come upon them they notice you. Taking them back, an errand or a story ends the step at once.
- Hirelings like Jenassa take part too: the game used to forget them once they walked into a part of the world that was not loaded, so their life never began.

### Getting about
- Travel takes companions: "Lydia, Uthgerd, wait for me at the Bannered Mare" sends both, walking together at the leader's pace (at most three). When you arrive, the leader greets you once for the group.
- NPCs can be sent to places named in SkyrimNet: your own marks, a content pack's places, another mod's travel markers. A room word ("the kitchen") means a room in their own building.
- "The Drunken Huntsman" and "Drunken Huntsman" are the same place. A location's marker that the game data puts inside another building is no longer used: everyone sent to the Drunken Huntsman used to wait in Belethor's shop next door.
- Asking someone to "fetch Olfina from the Bannered Mare" brings Olfina to you; it used to send them to the inn to wait.
- A fetch, and an arrival, could be handled twice when two checks saw it at the same moment ("Jenassa brought Ysolda" twice, "Uthgerd arrived at Drunken Huntsman" shown twice). Each is handled once.
- An NPC who arrives where you already are is no longer said to arrive "together with" you, nor, when they come into a room you are across, to find you arriving where they waited. Indoors the scene is told that you were there first; outdoors, only that you are both there.
- The Travel and Scheduling choices the dialogue model sees now say which is which: setting off now, even to wait somewhere ("go on ahead and wait for me at the inn"), is a trip; a plan is for a set later time. Asked to go ahead and wait, NPCs agreed and then chose neither.
- With SeverActions, whose own descriptions send "going ahead to a place" to a "Journeys" entry that SeverActions does not have, the Travel choice now says it is that entry.
- Times counted in words or past twelve are understood: "in two hours", "two hours from now", "in twenty minutes", "in 24 hours". They used to be read as no time at all, and a meeting then fell back to 6 PM ("in two hours" at dawn was a meeting that evening).
- After a meeting is over, the NPC takes a new task again. Asked to wait somewhere else, Elrindir agreed and then stood where he was. The meeting is kept in their own history as done, not as "attempted".
- An inn's bard sent somewhere stops his songs and goes. The game's bard quest plays one song after another while you are in the inn, and IntelEngine ended a song only when it caught him between two; while he sang he counted as talking, so the checks that would free him stood down. Mikael, sent to a meeting, played on past it. (A song SkyrimNet's own bard action has him perform, and the inn's conversations SkyrimNet keeps him in, still hold him until they end.)
- A late NPC who still reached the meeting place before you is no longer said to have found you "already waiting": the scene is told you came later still.

### What users reported, checked against this version
Every report in the Discord channels and on GitHub was looked up in this version's code before anything was changed (the list, with where each stood, is in the project's notes). Fixed here:
- **Carriage drivers and ferrymen** are never sent anywhere, whoever asks: the ferrymen of Dawnguard have a faction of their own and were never covered, and the dungeon master's own dispatches had no such rule at all.
- **A package that would not come off**: Remove on the dashboard and on SkyrimNet's package page now also works for someone being fetched or escorted and for a slot left half finished; the row stayed at "Removing..." for good.
- **Someone who kept seeking you after a load**: a visitor whose story had ended kept the walk-to-you package across cells until cleared by hand. Such slots are found and given back.
- **"Wait outside"**: someone sent out of the room you are in is no longer walked straight back in to you.
- **The same failure told a hundred times**: a place nobody can find or a person who cannot be found is told to the NPC once; told again within two minutes it is only logged. The narration gave the model a turn, the model tried again, and it went round at a hundred calls a minute.
- **Quest people left alone**: nobody in the middle of a scene, and nobody an open objective of yours points at, takes a task or is sent anywhere, at any level of the living world.
- **Other mods' packages**: a follower sent on a task loses SkyrimNet's and SeverActions' follow by name instead of every mod's package overrides (Nether's Follower Framework lost its home base that way).
- **Task actions missing after a load**: someone waiting at their destination was marked busy at every load, so the deliver-message action and its siblings were not offered.
- **The game's own civil war**: the simulation now reads how the war stands in your game. While it is undecided nobody wins it, nobody surrenders, and the Empire and the Stormcloaks never become friends; under the truce of High Hrothgar their fighting stops; once you have decided it, it is over, with the winner your game has. The Empire does not go to war with the Thalmor while the Concordat binds it. The dungeon master and everyone in Skyrim are told how it stands.
- **Faction names in any letter case**: "CollegeOfWinterholdFaction" and "CollegeofWinterholdFaction" are one faction (reports were refused, College soldiers came out as bandits). "Positive" is as good as "positive".
- **Soldiers who attacked you**: fighters called up for a brawl or a skirmish belong to their side and to nothing else; where their template is the game's bandits or thieves they went for you on sight.
- **Standing "reset" at login**: the bonus for being a member is given once, not at every load once your standing had worn down to nothing.
- **Politics off means off**: battles set earlier, skirmishes and faction ambushes no longer run with politics switched off; no assassin strikes in your own home; a faction's messenger is a person, not a creature; and another character's politics are no longer told to this one's people.
- **Speaking twice on arrival**, **the dead in gossip**, and **meetings at places or times nobody can make out** (refused with a word, instead of "this evening" or a meeting that fell through when the hour came).
- **Names that are not UTF-8** (mods' plugins in Russian, Chinese or accented Latin code pages) could stop a request or end the game in any of ninety-four places; the dashboard had been mended for it in 3.7.1.
- Found by reading the new code, not by anyone's report: one way the story watch could hang the game thread, and several ways a model's answer of the wrong shape could end the game.

### Dashboard
- The World page has a new card, "How People Stand With You": everyone whose standing IntelEngine has read from what passed between you (an acquaintance, a friend, a close friend, someone who has turned cold), and where it comes from. What is in someone's heart stays theirs to show unless you switch on "show everything". People SkyrimNet Relationships speaks for are on that mod's own page.
- **Skipping time does not hurry the world along.** Every pacing rule counted the game's clock alone, which you can turn forward at will: wait a day, and another, and you were owed a visitor after each wait and a new story of the town after each. Now moments also take time actually played (the game running, not paused, not waited or slept or travelled through): eight minutes of play between two moments of the director, four minutes of play in a town before a story of its own begins there, twenty minutes of play between two such stories. At the game's own pace those are what three game hours, two game hours and less than a game day already are, so ordinary play does not notice them; they hold when time is skipped or the timescale is high. What is urgent still comes. The world itself moves on as before while you sleep: talk travels and fades, an offer you did not take lapses, those you left behind get on with their lives, a battle nobody came to is decided. Played: a day skipped right after a patrol left the director at "76 s of play since the last moment: held back" with its budget full, and it opened again at 531 s; in town, four and a half hours skipped gave "22 s played here (240 needed)", a story began after four minutes of play, and a further day skipped gave "the last one began 11 s of play ago (1200 needed)". If you would rather have the clock alone decide, as it did before, there is a switch for it on all three settings pages: **"Skipped time counts toward the pace"**, off by default. On, a day waited through is a day, and a day's worth of moments is due after it. Played both ways: off, a day skipped left the director at "44 s of play since the last moment: held back"; switched on, its next look said "66 s of play since the last moment: a moment may land"; thrown on and off again, the saved settings followed each time.
- **Rows in the MCM that did not fit now do.** The MCM writes a row's value in capitals from the right edge of its column, and in the Living world section two values lay over their own labels ("Interruptions at bad moments" under "ONLY WHEN URGENT", the quest setting under "FOR IMPORTANT REASONS") while a third label ran into its number. A setting has one name on all three pages, so the names are shorter everywhere: "Interruptions at bad moments" offers Never, If urgent, Realistic; "Quest NPCs may move" (it was "NPCs of running quests may move") offers Never, If important, Freely; "A follower left behind moves on (days)" lost its "after". Nothing changes in what they do, and a settings file that still holds an old word is put right when the game starts: a value the file holds that cannot be read (an old word, a typo) is replaced by what the game has, so SkyrimNet's page shows what is in force. On the Active Tasks page a busy slot no longer writes "SINMIR: TRAVELING TO DRUNKEN HUNTSM" over "Slot 0:": who and what is the row's own text, and where they are ("(near The Bannered Mare)") stands beside the Clear button below. All of it looked at in the game.
- **"Check interval" is Classic's pace only.** Above Classic there were two settings for the same thing: "Check interval" (how often the dungeon master looks by the clock, 3 game hours by default) and "How often something happens" (calm, normal, lively: what actually comes of it). The second decides; the first could only get in its way, and set to a day or a week it starved the director whenever you stayed in one place. Now, above Classic, the dungeon master looks when you arrive somewhere, when you wake, and every three game hours besides, whatever "Check interval" says; a look that finds the day's share already used ends before any model is asked. At Classic the setting is the pace, as it always was. The dashboard shows the row dimmed above Classic and says why.
- At "Classic" nothing is read of how people stand with you (a reading is a model call, and Classic is the world as it was before 4.0).
- Settings that still described 3.8 say what 4.0 does, on SkyrimNet's page, the dashboard and the in-game menu alike: the quest kinds (a bounty, someone held, a keepsake, and what switching each off takes out of a town's story), the story types (what "ambush", "stalker", "work for you" and "a faction's patrol" mean now), "Check interval" (the fallback clock, not the pace), "No restriction" for how far people travel (the director keeps other holds at home all the same), "Next look by the clock" on the Story page, and the card of the dungeon master's own quest. A Tasks card that could never show is gone. No setting was renamed or moved.

### From Gerkinfeltser's pull requests
Eight pull requests against 3.8.3, taken into this version (six as they are, under his name; two adapted, see the native repository's commit):
- The Politics tab keeps its faction colours after a settings reload.
- Maintenance runs once per load (the DLL's own call three seconds later slipped past the two-second guard and ran task recovery a second time).
- Travel history reads "Went to Riften but gave up waiting" again where the game handed the task type back in another script's spelling.
- Director tab, political dispatch: Generate says why it failed when SkyrimNet gives a reason; a war declaration between two factions that cannot be at war is stopped in the form with a hint; a generated relation change has to fit the event (a betrayal is never +8); the field is held to -15..15.
- English names of the game's places resolve on a game in another language (a table of 1,489 names under `SKSE/Plugins/IntelEngine/placenames`, more languages can be added as files); names with accented and Cyrillic letters are matched without regard to case. Loaded in 3 ms. Not tested on a game in another language yet.
- Dashboard: a folded card frees its space on every two-column page.
- Battles: a marker soldiers may still be walking to is never deleted under them (his finding: two crashes at the end of a skirmish in 3.8.3; 4.0 deleted markers the same way in three places), and the clean-up after an attempt on a leader's life cannot run twice at once. The rest of that pull request mended the 3.8 skirmish, which 4.0 replaced with a small battle on a field of its own.
- A task no longer wipes other mods' package overrides: 4.0 had this fix already.

### Fixes to 3.8
- **Loading a save could leave the whole mod asleep.** The mod's start-up on load guards against running twice by comparing the game's clock of real seconds with a time kept in the save. That clock restarts with the game, so a save loaded at about the same second after launch as in the session that made it (start the game, load straight away: much the same second every time) was taken for "a call a moment ago" and skipped. Nothing was monitored after that: a visitor walked up and stood there, tasks were not followed, until the next load happened to fall on another second. Every load now carries a number of its own, and only a second call after the very same load is skipped. Found in a test run where Anoriath stood in front of the player for five minutes with his offer unsaid.
- A new game no longer leaves IntelEngine stuck at start-up. On some new games started on 3.8.2 the dashboard said "settings not available" and the IntelEngine MCM page froze: the scheduling script called the main script while it was still starting, and each waited for the other. It no longer calls anything while starting; its timer is set a moment later by the start-up routine, as on every load. Reported by LouisCCW; the cause was found by Gerkinfeltser from a stack dump. A save already stuck this way may not recover: start a new game on this version.
- Sparks and other lightning bolts are visible again (invisible since 3.8.0; the spell still did its damage). The game keeps one spelling of every name, whatever its case, and the first one loaded wins. The lightning mesh looks up "Generation" exactly, and a script parameter called "generation" took its place. The parameter has another name now. Reported by Cannottell-wq; the cause was found by Gerkinfeltser. Restart the game fully after updating. If bolts stay invisible, another mod in the load order has the same kind of name.

## 3.8.3 — 2026-11-19

Four fixes. The DLL and four scripts changed (NPCTasks, StoryEngine, Core, Travel); the ESP is unchanged. Install over 3.8.0, 3.8.1 or 3.8.2; saves and settings carry over.

- NPCs can travel to SkyrimNet's Named Places. SkyrimNet already offered them to the AI as destinations ("Kitchen"), but IntelEngine could not find them, so an NPC sent to one went nowhere or somewhere else. A Named Place is now looked up by its exact name first. Needs SkyrimNet v1.0.0-rc1 or newer; on older versions nothing changes.
- "Take me to …" no longer sends the NPC after someone else. Asked to take you somewhere, the AI sometimes picked the escort action with you as the one to escort, and the NPC set off toward another character whose name contains yours. The NPC now heads to the place and waits for you there.
- Sparks bolts are visible again. A word in one IntelEngine script clashed with a name the game's lightning effect looks up, and the bolt drew nothing (galanx/IntelEngine-GamePlugin#35).
- Children run errands again. The task check turned them away from errands and fetch tasks; carriage drivers are still never sent. By Galanx.

## 3.8.2 — 2026-11-14

One timer fix, and the save converter moves to its own download. The DLL and ESP are unchanged from 3.8.1; four scripts changed (Core, Schedule, StoryEngine, Battle). Install over 3.8.0 or 3.8.1; saves and settings carry over.

- The game-time timer goes off again while NPCs are busy. All IntelEngine scripts share one game-time timer, and the story engine restarted it every few seconds while any task ran, so it went off only when you waited or slept. Scheduled tasks, scheduled battles and the story engine's game-time checks wait on it. A new story dispatch also switched it off outright. Now a script only moves the timer earlier, never later. On a full load order, with an NPC travelling and no waiting: before, the timer was restarted 170 times in about ten minutes and went off 0 times in about three game hours; with the fix it went off every game hour. A scheduled battle was not tested live.
- The legacy save converter is no longer in the mod package. Upgrading a save from IntelEngine 3.5.2 or earlier? Download the unchanged converter separately: https://github.com/galanx/IntelEngine-GamePlugin/releases/tag/save-converter-1

## 3.8.1 — 2026-11-14

Fixes for things you notice in play, by Galanx. Install over 3.8.0; saves and settings carry over.

### NPCs on a task

- NPCs no longer dawdle before they leave. Whether an NPC "has not set off" or "is stuck" was not looked at while they had a dialogue target, and SkyrimNet leaves that set to whoever they last chatted with, for minutes. On a full load order many NPCs therefore stood where they were (one at the inn's door for three minutes, twice) until the task's time limit ended it. The two checks now stand down only for an NPC who is really held by talk: in the game's dialogue menu with you, speaking, about to speak, or having finished a line a moment ago.
- An NPC no longer calls off a task you gave them by themselves. Their own cancel was refused while you stood near and taken when you were away, which is exactly when nobody can have told them to stop: the AI answered the line about their setting off with "stop current task", and the NPC you had sent never arrived (seen twice in a row, 47 and 52 seconds into a trip). Away from you it now counts only when you have just said something within earshot ("Come back!"). Cancelling from the dashboard, the MCM or SkyrimNet's package page works as before.
- The cancel action's description tells the AI the same thing: it is for when you tell them to stop, not for when they have set off, arrived or lost interest.

### How a battle ends
- When a battle is over the field empties the way a field does: the fighting stops, the beaten run for it, the winners put their weapons away and walk off, each side its own way. Until now nobody was told the battle was over. The survivors stood where the fighting had stopped, and three minutes later every soldier and every body was removed in one stroke, wherever you were looking.
- Nobody is taken out of the world in your view any more. A soldier who has walked off is removed once you cannot see them: out of the loaded area, or far off and off screen.
- The dead stay where they fell for six hours of game time, also when you step indoors or travel away and come back. After that they are cleared away when you are not looking. (Skyrim itself keeps only about fifteen dead in one place: after a big battle it removes the others on its own, as it always has. In three test battles 14 of 25 to 29 dead were left after three minutes.)
- After a battle you fought in, one of your side comes over and says a word, then follows the others. Instead you were always told "none of your allies remain to celebrate", with your allies standing around you. If your side fought too far from you for anyone to come over, nothing is said.
- The stand-down comes first and the announcement after it. The fighting used to go on through the pause and the announcement of who had won.
- The battle script gets hold of its soldiers. It asked the DLL for them under the name "formIds"; the game keeps one spelling per string and handed over "formIDs", the spelling of a variable in another IntelEngine script, and the DLL answered with nothing. So the script never knew a single soldier of any battle: it could not start the first clash (the log's "Kick-started 0/6 combat pairs"; the soldiers found each other on their own), and it had nobody to send home at the end. The DLL now matches such names in any spelling.
- Two armies raised from the same soldier list fight each other. Members of one list are friends through the faction they come with, which outranked the two battle sides: both armies stood side by side (seen with both sides from the bandit list). A soldier now belongs to their battle side alone.
- When a faction's soldier list is not there, the battle no longer goes straight to bandits. The on-screen battle now looks a list up the way every other spawn does (by name, by enumeration, by name prefix for the lists a Requiem-style overhaul replaces, by the form id of the stock lists in Skyrim.esm); it used to try the name alone. A list that is found but yields nobody counts as missing. A faction without a usable list raises its first ally's soldiers: the Political Engine realms come without a list, so a realm allied to the Legion now fields Legion soldiers where both armies used to be bandits. Generic bandits are the last resort, and they do fight now (see above). `soldier_template` can also be written as a form id ("0x0001FC5B", or "MyMod.esp|0x000801" for a mod's list).
- A battle that begins within three minutes of the last one can no longer be reset by the earlier battle's wind-up.
- A battle that is cut short (its time limit, a save loaded in the middle of it) ends the same way: the soldiers walk off instead of vanishing on the spot.

## 3.8.0 — 2026-11-14

### Contributors
- **Gerkinfeltser** developed 3.8: the sections Director, Story travel and arrival, Stories and NPC scenes, Off-screen placement and fetch, Politics and Other below, with the Magelight prompts, the Political Engine bridge and the faction fragments.
- **Lanosity** wrote the natural-language time parser.
- **Galanx** reviewed the release and wrote the sections Stuck NPCs and package handling, Meetings and visits, Prompts, dashboard and controller, Wars that end stay ended, Working with SkyrimNet, Assassins and soldiers that turned on the player, and Fixes to 3.8 changes found in review.

### Director
- Director-dispatched actions no longer show the Allow/Deny confirmation (the per-action "What followers can be asked to do" setting still applies).
- Story replacement accepts Director fields and explains refusals; a cancelling story must finish before it is replaced.
- Generate requires real NPC names and no longer makes another NPC approach you in informant narration; NPC suggestions rank exact names first.
- When an NPC can't be sent because they aren't loaded (they only exist near their home), the Director now says so instead of "no unique match".
- The dashboard hotkey is ignored while you type in a text field.
- "Skip Action for Followers" is now "What followers can be asked to do" in the MCM, on the dashboard and on SkyrimNet's settings page, with every action on by default. Nothing changes in what followers do: the old list of switches that were off read as if the actions were switched off for followers.
- Informant stories have their own form: Informant NPC, Subject (an NPC, a faction or you), optional Source and a required one-sentence Rumor. IE writes the informant's line, so there is no Narration field.
- A rumour is refused, with the reason, when it doesn't name the Subject as a whole word ("Ria" inside "Victoria" doesn't count) or starts with an -ing word.
- NPC Social gossip has a Subject field; the rumour is stored as "<Subject> <what they did>".
- The story type is never chosen by the LLM: a type left on (auto) must be picked before Dispatch, and Generate fills only that type's fields.
- Generated interaction narration describes the scene instead of copying a fact; generated gossip says how and where it was told.
- A social scene for two NPCs already standing together near you plays right there (it used to be applied off-screen).
- With Magelight UI installed, the Allow/Deny, door-knock and quest-offer prompts open as a Magelight page in the dashboard's style (keys 1-3, Esc = the do-nothing answer, timer bar on the knock). A prompt waits while the dashboard or another Magelight window is open. Without Magelight, the Papyrus MessageBox is used as before; it is now only needed without Magelight.
- Director quests need a Plea for help (and a Victim for rescue, an Item description for find_item) before Dispatch; Generate no longer picks the current location or a player home as the quest location.

### Story travel and arrival
- A story NPC counts as arrived after 15 seconds within talking range.
- Arrival timers use real time; a late NPC is re-placed once behind the target, then the story aborts with a notice.
- Story arrival waits until save-load recovery finishes. Director stories ignore the Hold Restriction; automatic stories still turn back and say why.
- Story NPCs who become your teammate are released from linger; linger timeouts survive pausing.
- Lingering NPCs are released after one game hour, so waiting or sleeping frees them (see "Meetings and visits" below for how that limit works now); the linger release distance keeps its default of 800, with the minimum lowered to 300.
- The story watchdog no longer marks an NPC who already arrived as "never finished", and strips travel packages when it resets a story.

### Stories and NPC scenes
- NPC-to-NPC scenes are narrated only within SkyrimNet's hearing range; otherwise the pair waits for you and plays when you come close, or is applied as facts only when it times out.
- An informant's rumour is one checked sentence; IE builds the arrival line from it, and the informant remembers why they came.
- Two NPCs with the same name (two "Gamlunda"s) resolve to the one the DM was shown.
- Spawned actors (battle soldiers, ambushers) are never picked for stories or gossip.
- The Story DM sees which story types each candidate can take, and a Markdown code fence around its reply no longer breaks validation.
- A seek_player story's memory is no longer added twice.

### Off-screen placement and fetch
- NPCs travelling while unloaded are now placed near the target when their estimated travel time runs out (they used to walk on indefinitely).
- A fetched NPC walking toward you is no longer sent home early, and one already beside you is no longer teleported away across an exterior cell boundary.

### Politics
- New `war_allowed:` section in factions.yaml decides which faction pairs may go to war (default: any two factions of type `military`, so guilds and families stay out of it). Entries can be faction ids, display names, types or `*`. Political Engine realms never go to war.
- When the Political DM ignores the "declare war" rule for the most hostile allowed pair, IE declares the war itself (skipping factions whose leaders are all dead); war declarations for pairs that aren't allowed are refused.
- The Empire and the Aldmeri Dominion are neutral to each other: the Legion and the Thalmor are no longer allies, and their starting relation is 15 (was 50).
- A battle result for two factions that aren't at war is recorded as a border skirmish, and no soldiers spawn.
- Fighters left standing after a brawl or skirmish are removed shortly after it ends (they used to stay in the world forever).
- Loading a save resyncs the "at war" flags with the save's actual wars.
- Major political news (wars, battles, treaties, Political Engine developments) reaches every NPC; smaller events reach the factions involved and, for political factions, people in their hold. Repeated events show once with "(reported N times)".
- The Political DM no longer repeats one war's battle, counts a scheduled battle as that war's battle for one game day, and is told which wars can't have a battle yet.
- Political Engine: realm rulers (including puppet realms) are shown as faction leaders; a realm without a ruler clears its leader; a ruler change becomes news; IE resyncs when Political Engine (re)loads; realm allies and rivals follow live sides; factions can set `pe_side` (the Thalmor map to the Aldmeri Dominion).
- The dashboard colours faction names by Political Engine side and labels your own puppet and vassal realms.
- The Politics Enabled toggle comes first in the Faction Politics MCM page.
- Director Politics: a surrender names the Surrendering faction and the Victor, and is refused unless the two are at war; Generate never drafts war declarations, surrenders or peace offers.

### Other
- Battles no longer stop the story and quest timers when they reset.
- Soft stuck recovery no longer waits on latent calls; stuck detection samples at most every three seconds.
- Informant gossip keeps the subject's name.
- Notifications and Papyrus log lines use plain dashes (em dashes showed as "â€”").
- Political Engine integration is off by default and marked experimental. It needs the mod Political Engine and does nothing without it (the dashboard greys the switches out then). Switch it on in the MCM (Faction Politics), on the dashboard's Settings tab or on SkyrimNet's plugin settings page; a `settings.yaml` that already says `pe_integration: true` keeps it on. Its realms join the factions on the next load.
- Optional Political Engine API v3 bridge: public campaign news reaches the Political DM as faction-less rumors, with one organization reaction per development and a persisted MCM/dashboard toggle for reaction relation changes. IE's own wars and battles are unaffected.
- Faction fragments: extra `factions.d/*.yaml` files add or replace factions and relations; a Political Engine fragment adds the nine vanilla realms as factions, with live rulers and the player's realm passed to the Political DM, when Political Engine is active.
- Action and scheduling prompts ask for exact in-game place names in the game's language.
- Extra travel and Director diagnostics at DebugLevel 4.

### Stuck NPCs and package handling
- All monitoring runs on one shared timer with one owner. Scripts used to cancel or re-arm it for each other: switching the story engine off, or a battle ending, could freeze every trip, task and schedule.
- A task slot that changed hands while a handler was waiting is no longer wiped or marked "arrived" by the old handler; half-finished slots are cleaned up hourly.
- An hourly sweep releases NPCs who still run an IntelEngine package with no task behind it; "Reset all tasks" in the MCM does the same at once.
- NPCs with no routine of their own (many mod-added NPCs) are walked home when a trip, meeting, task or visit ends, instead of standing where it ended.
- No recovery move happens in the player's view: a stuck NPC who is being watched gets a fresh path instead of a hop, and unseen arrivals come in through the door indoors or from behind outdoors. "Behind the player" used to be "south of the player".
- Indoors nobody is placed 2000 units away (outside the building's shell) or leapfrogged through a wall.
- An NPC who is talking is not treated as stuck, and one who is asked to do something in conversation finishes the sentence before turning to go.
- During a task IntelEngine removes only its own packages, so a follow or wait order from another mod survives the task. If such a package blocks a trip it is cleared and the trip goes on.
- An unknown place name, an unknown target or no free slot no longer cancels the task the NPC already had.
- Two NPCs given a task in the same instant no longer end up in the same task slot. The second one went, the first task was dropped without a word, and that NPC then refused the same request as "already on it". A slot is now taken in the step that picks it. (3.7.1 could do the same.)
- Trips: a disabled NPC's trip ends; a long road walked together with the player is not cut off at seven hours; the time limit no longer restarts on every load.
- Fetch, deliver, escort, search: a search has an overall limit and the searcher waits on the spot when you fall behind; an escort without "wait" lets the NPC go at the destination; a fetched NPC's visit ends on its own; waits are measured in seconds instead of monitoring passes; carriage drivers are never fetched or escorted.
- Stories: a refused faction courier gets their aggression back; an ambusher gets their own essential flag, aggression and confidence back; quest enemies, bosses and ambush soldiers are removed once out of sight; a dead guide ends the guiding, not the quest; a visitor walks the last stretch; two NPCs stay together for the length of their scene.
- Battles: spawned soldiers are remembered across a restart and removed; your crime factions are restored after a battle you joined; an assassin is no longer deleted at the moment of striking.
- An NPC sent on a task while the inn's bard is singing no longer sits through the song first, and one caught by a song on the way out walks on. The game takes the people in the room into the bard's audience and holds them until the song is over, whatever they were told to do.
- The inn's own bard can be sent on a task: he finishes the song he is singing, the next piece does not start, and he goes. He plays again the next time you come into the inn. He used to stay at his spot whatever he was told, because the game holds a performing bard in a scene.
- An NPC the game is holding in a scene or a quest is not treated as stuck: no recovery moves, and no line about their feet catching on something from someone who has not left their chair.
- That patience is for someone who is really held. An NPC whose travel package has gone missing gets it back at the next stuck check; they used to be left standing for two minutes first (found by Gerkinfeltser).
- An NPC can no longer cancel the task they were just given with their own first reaction to it (a fetch was called off six seconds in, when the AI answered its start with "stop current task"). A task you cancel yourself ends at once, as before.
- That protection covers the first 45 seconds of a task. For a task carried over in a save it could come back for 45 seconds in a later session; it is dropped when a game is loaded (found by Gerkinfeltser).
- A message delivered out of your sight is reported back again when the messenger lives where you are waiting. They were back home before the handover was counted, so it was taken as delivered in front of you: no way back and no report.
- A task that runs out of time is finished quietly when you cannot see the NPC, also when the game still has them loaded out in the street while you sit indoors (it keeps a town's outdoor cells in memory once you have walked through). It used to be called off as if you had been watching: an escort was cut off three times in one evening on a full load order.
- An NPC who reaches a named building unseen is inside it, like one who walks there in view. They used to be left outside the door.
- A quest whose guide you leave behind no longer stalls. With "Lead the way", the quest's enemies, captive or chest appear only once the guiding is over, and it ended only with the guide beside you at the place: go ahead into the dungeon and it held nothing of the quest until you came back out to her (and she was moved near the place again every three seconds meanwhile). The guiding now ends when she gets there unseen, and at once when you are there already.

### Meetings and visits
- An NPC who is already inside the meeting place has arrived (they were sent to its outside door and the meeting was called off).
- A meeting is not called off because the NPC was talking, fighting or out of sight when it was time to leave.
- An NPC waiting at the door while you are inside walks in (the order used to be re-issued every three seconds, so the walk never got anywhere).
- After a load, an NPC waiting at a destination keeps their place.
- A visit no longer ends one game hour in, whatever is being said. It lasts while the NPC is talking with you and a little after, and six game hours at most. This applies to meetings, errands, story visitors and fetched NPCs.
- Times are understood in many more forms ("in 2 hours", "tomorrow at 6", "at dusk"). The natural-language time parser is by Lanosity.
- More spellings of a time are read: a spelled-out hour with am or pm ("six a.m."), and a clock time with the part of the day ("6:30 in the evening" was taken for half past six in the morning). A bare hour for another day follows the waking hours: "tomorrow at 6" is the evening, "tomorrow at 9" the morning.

### Prompts, dashboard and controller
- The choice popup scales with the screen (4K, ultrawide, VR), answers on key release (Enter no longer leaks into the game), takes Left/Right and E, and takes a gamepad when Magelight's gamepad layer is there. Its footer says what Esc answers.
- The task-permission prompt has a 20-second limit; no answer is a silent deny.
- The dashboard has a larger layout and can be driven with a gamepad or the arrow keys.
- A Director political event that is refused now says so (it showed "Sent" and did nothing).
- The middle answer of a prompt reads "Deny" (it showed as "deny").
- The MCM offered 500 as the default of "Visit ends when you walk away"; the default is 800. "Wait at a destination" moves in steps of one hour on the dashboard, as it does in the MCM.
- One name per setting (asked for by Gerkinfeltser). The MCM, the dashboard and SkyrimNet's plugin settings page each had their own name for the same setting ("Max Travel Time", "Max Travel Time (days)", "Longest journey (days)"). All three now use the names of SkyrimNet's page, in plain words, and so do the README's tables. The same goes for the names of the options: "Followers only", "Block civilians only", "Same hold (except followers)". Some of what you will look for under a new name:
  - Story types: "Seek Player" is "Someone comes to see you", "Informant" is "Someone brings a rumor", "Road Encounter" is "A meeting on the road", "Message" is "A message is delivered", "Quest" is "Someone has work for you", "Ambush" is "An ambush", "Faction Ambush" is "A faction's patrol hunts you", "Stalker" is "Someone follows you unseen". The Director, the notices and the log keep the short names, and each switch's help text says which one it is. (Two of these showed in lower case in the MCM before.)
  - Tasks: "Action Confirmation Prompts" is "Ask before starting", and the actions read "Go somewhere", "Deliver a message", "Fetch someone", "Escort someone", "Search for someone", "Arrange a meeting", "Fetch someone later", "Deliver a message later". "Max Concurrent Tasks" is "NPCs on a task at once", "Default Wait Hours" is "Wait at a destination", "NPC Release Distance" is "Visit ends when you walk away", "Meeting Timeout" is "Wait for you at a meeting", "Meeting Grace Period" is "On time until".
  - Stories: "Enable Story Engine" is "Stories", "Max Travel Time" is "Longest journey", "Teleport on stuck/timeout" is "Move a stuck traveller along", "Quest Timeout" is "Quest expires after", "Danger Zone Visits" is "NPCs sent into dangerous places", "Player Home Visits" is "NPCs sent into your home", and the quest types are "Quest kinds" ("Clear out enemies", "Rescue someone", "Find an item", and the three for factions).
  - NPCs among themselves: "Enable NPC Interactions" is "NPCs visit and talk to each other", with "Kind: one NPC goes to see another", "Kind: gossip passed on", "Check interval" and "Rest per NPC".
  - Others: "Debug Mode" is "Debug messages"; Auto Dynamic Bio's "Enabled" is "Refresh an NPC's profile after much talk"; politics' "Tick Interval" is "Check interval".
  - Nothing is stored under a name: your settings and your `settings.yaml` are untouched.
- Settings that showed or said the wrong thing (found by Gerkinfeltser):
  - The dashboard's switches for the two kinds of "NPCs among themselves" (one NPC goes to see another, gossip passed on) always showed ON; they show the real state now, and the two are no longer listed among the Story tab's story types.
  - "Story NPC Cooldown" is gone from the MCM and the dashboard. The game used the longer of it and "Long absence", so with the default of three days its 6 to 72 hours changed nothing. "Long absence" is the setting.
  - "Allow NPC death in rescue" is gone from the MCM and the dashboard: nothing read it, a rescue's victim is always kept alive.
  - Hold Restrictions no longer claims "Default: Same Hold (Civilians)" for every story type (true for three of seven): the MCM names each type's default in the help text, the dashboard beside the type.
  - The help of "Debug messages" (Debug Mode until now) says what it does (notices on screen; the Papyrus log has them either way) and points to DebugLevel=4 in IntelEngine.ini for the DLL's log.
  - Dashboard sliders show as many decimals as their step has (0.25 days showed as 0.3).
  - Director quest form: the fields that one sub-type needs (Victim, Item description) carry a yellow star until a sub-type is picked, then the red one or none.
  - `min_event_interval_hours` is gone from settings.sample.yaml; nothing read it.
  - The Hold Restrictions options read "(except followers)" throughout; six of the seven groups had "(-followers)".
  - README: Danger Zone default, Story Check Interval, the Max Travel Time row, the quest sub-types, the hold defaults, the prompt's 20 seconds, and the visit clock that also ends a lingering visit. FAQ: the cooldown tip.

### Wars that end stay ended
- A war that ends leaves the two factions at an uneasy truce instead of still being at each other's throats, so the same pair no longer declares war again after every cooldown, a little worse off each time.
- A war that ends by exhaustion or collapse is recorded as a surrender or a ceasefire, something NPCs can hear about and talk about. It used to end in the database only, with nothing in the world to show for it.
- A faction's own `war_threshold` is honoured when a war is declared in code, not only when the Political DM proposes one.

### Working with SkyrimNet
- An NPC who is given a task in conversation finishes what they are saying before they set off, also when their answer is still being synthesized. IntelEngine now hears from SkyrimNet itself that a line is on its way; it used to ask the game whether the NPC's mouth was moving, which is not yet the case in those seconds, and wait seven seconds at most.
- A running task shows on SkyrimNet's Package Manager page as a row of its own ("IntelEngine task: travel, Dragonsreach"). Remove on that page cancels the task cleanly, the way IntelEngine's own dashboard does, so an NPC you want back can be freed from either place. Needs a SkyrimNet with the package manager; older versions are left alone.
- IntelEngine's settings are on SkyrimNet's dashboard too, on the plugin settings page: stories and their types, how far NPCs travel for each kind of story, quest kinds, NPCs among themselves, tasks and their confirmation prompts, meetings, politics. A change there takes effect in the running game when you press Save; a change in the MCM or on IntelEngine's own dashboard shows there a few seconds later.
- These settings now belong to the installation, not to one save: a new game starts with what you set. A save from before this update keeps its own settings the first time it is loaded and writes them to the shared file.

### Assassins and soldiers that turned on the player
- An assassin sent after a faction leader goes for that leader and nobody else. They were made hostile to every neutral in reach, the player included, and attacked whoever stood nearest once the leader was down or out of reach.
- The pause between an assassin reaching the leader and striking no longer runs into the cleanup timer. When the walk had taken fifteen seconds, the assassin was taken off the books during that pause and then struck anyway: an attacker nothing ever removed. This is the assassin that "kept attacking".
- The attempt ends when the leader is dead, on their knees (leaders who cannot die) or gone; the assassin then stands down instead of looking for the next target. An attempt on a leader who has left the room is called off.
- Soldiers spawned for a brawl or a skirmish fight each other and their factions' enemies, not bystanders. Several soldier types, and the stand-in used for Political Engine realms, attacked any neutral on sight.
- Spawned fighters who survive their event put their weapons away, and are removed at once where nobody is looking.
- A faction ambush only comes from a faction that is hostile to you (standing -40 or lower), and stays small until the feud is deep. The model could pick any enemy of one of your friends, or a faction that does not exist.
- The people who remember an assassination attempt are those who stood around the victim. They were counted around you, so someone two rooms from the attack remembered having witnessed it, and the victim remembered having "witnessed an attempt on" a person with their own name; the victim now remembers being attacked.

### Fixes to 3.8 changes found in review
- NPC gossip without a subject no longer starts with a blank.
- The second NPC of a scene resolves again when they are not in the first one's cell (the pair was dropped as unresolved).
- A model answer with a field of the wrong type (`"gossip": null`) is rejected instead of ending the game.
- An informant rumor may start with "During", "King", "Something" and similar words.
- Choice popup: a lost race for the screen is noticed at once, a late entry no longer leaves the game paused on a hidden page, and a page that failed to load is not reused.
- A pair of NPCs waiting for you to come within hearing waits for the full time, not thirty seconds.
- A `factions.d` fragment with an unknown `requires:` line, or saved with a byte-order mark, is not loaded for everyone.
- A battle in a plugin whose file name is not plain ASCII no longer throws while it is recorded.
- An automatic story that is given up on (the NPC cannot reach you, or turns back at a hold border) says nothing on screen: it used to name a visitor you never saw setting out. A story you dispatched from the dashboard still reports back.
- A story NPC counts as having reached you only on the same floor, as travel arrivals already did; they used to arrive and speak from the room below.

## 3.7.1 — 2026-11-04

- The dashboard no longer goes blank when a game or mod name has invalid text encoding; it shows � instead.
- Fixed a crash near some modded NPCs whose faction list contains a non-faction record; the NPC is logged once so the mod can be found.
- MCM Hold Restriction toggles now save when clicked (they were unreachable in the MCM; the dashboard Settings tab already worked).

## 3.7.0 — 2026-11-03

- **Requires SkyrimNet Beta 27 or newer** (travel prompt uses the `get_place_names` decorator).

### Director
- Add Generate and draft controls for Story, NPC Social, Political, and Action forms. Generate is experimental; review drafts before dispatch.
- Keep chosen identities and edited text on re-roll, suggest distinct nearby participants, and guide required fields, destinations, and NPC motives.
- Add optional Action Execution reasons remembered only after a successful start, failure notices, busy confirmations, and Story/Social `queued: starts on dashboard close` feedback.
- Clarify that Story/Action toggles govern automatic stories and AI-chosen actions, not Director requests; Action changes need SkyrimNet Reload configs or a restart.

### Dashboard
- Save Director drafts across reloads; add searchable NPC/faction pickers, resizable text fields, clearer hints, and collapsible sections.
- Add optional Magelight hosting alongside PrismaUI, group actions by category, and fold packages into Tasks with recorded task origin, time, and reason.
- Show in-game calendar dates and faction leaders in Politics. Record completed Story/Social outcomes in SkyrimNet History, subject to its audience filters.

### Fixes
- Prevent duplicate arrivals and stale Story/Social callbacks from repeating outcomes or changing newer dispatches.
- Preserve cancellation/replacement state, improve moving-target arrival checks, and record attempted versus successful task outcomes accurately.
- Improve exact NPC and faction-leader matching, preserve full dynamic actor IDs, and reject missing delivery targets without replacing existing tasks.
- Reject same-faction political pairs and incomplete or invalid generated fields; preserve valid draft fields for review.
- Fix Director cancellation/conduct-report feedback and reason facts; preserve the selected same-name actor through Action Generate.
- Keep localized place names intact in action and DM prompts.

## v3.6.2

- Save converter: convert caches on temporary (0xFF) actors and orphaned global caches in place instead of refusing the whole save, and refuse a save whose caches are already in the 3.6 format (for example a later save made from an `_IEconverted` one). Output is readable multi-line text and warns against loading converted saves under any IE 3.5.x. Live: a converted ADT save loads with correct prompt text.
- Fix duplicate quest/message courier arrivals: the travel poll and the proximity callback could both handle one arrival, injecting blank-then-full facts and raising None errors after cleanup. Stale arrival continuations now stop without touching a newer dispatch. Live: one arrival, facts once, one cleanup.
- Dashboard "Cancel quest" after a courier arrives now frees the courier's task slot and package. Live: passed.
- Dashboard hotkey only toggles while Skyrim has focus and the configured modifiers match exactly (`0` no longer fires on Shift+0); documented default is Shift+7. Live: passed.
- Changing the dashboard hotkey on the SkyrimNet settings page now applies as soon as you click Save, without a restart. Live: owner-verified.
- Courier story facts are injected when the courier arrives, not at dispatch, so an aborted courier leaves no facts. Live arrival injection passed; live rejection is untested.
- Persist all four politics settings through shared native setters used by the MCM and dashboard. Politics initialized while disabled can be enabled later without restarting. Live: cold-load persistence and same-session enable passed.
- Print world knowledge shared by every Story DM candidate once, while preserving each candidate's additional facts and silent fact-check constraints. Zero or one candidate keeps knowledge local. Offline production-code and full-prompt checks passed; live untested.
- Truncate cached and prompt text on UTF-8 character boundaries.
- Remove unused Dialogue Safety Net and Director pending-parameter natives, their private backing code, and matching Papyrus declarations. Rebuild `IntelEngine.pex`; pair it with the matching DLL. Director parameters remain in the existing ModEvent JSON payload.

## v3.6.1

- Rebuilt bundled save converter to stop a Defender false positive (Wacatac.B!ml); no functional changes.

## v3.6.0

- Install the player FAQ, legacy save converter and drag-and-drop launcher for everyone. Retain the visible second FOMOD page with Required tools; fresh games do not need conversion. Convert an eligible old save before loading it with 3.6.0.
- Story DM skips ticks when all eight player-facing types are excluded, lists only currently allowed types in the prompt, and discourages repeated seek-player NPCs and long-absence motives. Rebuilt the StoryEngine script from source; offline exclusion and prompt-render checks passed. In a natural two-hour soak with `seek_player` disabled, 12 prompts omitted `seek_player`/PRIME. The automatic all-eight-types-off skip passed live; nonzero excluded-count filtering and natural disabled-pick rejection remain unobserved.
- The shared SE/AE/VR DLL should work in VR; partly tested on an emulated headset: startup/health, NPC/location lookups, MCM/Allow-Deny, travel arrival, two manual saves and a cold reload passed. Full acceptance remains untested for message delivery, fetch/escort, cancel, travel cleanup, VR overlay bios, dashboard, real-headset behavior and frame timing. The MCM right column is clipped on the emulated rig because of a Devkit emulated-window artifact; real-headset presentation remains untested. One automated-save attempt hung; this does not establish an IntelEngine defect.
- NPC Social DM snapshot/callback work uses the main-thread task queue and generation guards. SE/AE soaks passed; the 1.5.97 crash report on the original IntelEngine repo is not confirmed fixed.
- Cancellation was verified on Skyrim 1.6.1170 and 1.7.104: the slot, busy state and task cleared, with no success-history entry added.
- Fix Native #18: Bio Content Library base bios and overlay precedence verified on SE/AE 1.6.1170 and 1.7.104; base bios only verified in VR. Dynamic save-layer behavior was checked offline only.

### Offline legacy-save fix mode
- Refuse native rendered-cache assignments with missing values, including whitespace/NUL aliases hidden in opaque fields, before they can overwrite a repaired cache with empty data.
- Limit converter content validation to IntelEngine rendered-cache targets. Preserve other mods' blocks, duplicate unrelated serialization IDs and non-cache keys/values byte-for-byte, including control characters. Keep framing/count checks, refuse duplicate PapyrusUtil owners or STRV records and ambiguous targets, and verify all non-target bytes unchanged except the required enclosing length fields.
- Accept SKSE64 2.2.7 and 2.2.8 alongside 2.2.6 for Skyrim 1.6.1170, following the [SKSE release history](https://github.com/ianpatt/skse64/blob/v2.2.8/skse64_whatsnew.txt). No additional Skyrim runtimes are accepted.
- Add a player-oriented one-save fix command for eligible IE 3.5.2-or-earlier saves on Skyrim 1.6.1170/1.7.104 and VR-capable IE 3.5.1-or-earlier saves on VR 1.4.15 / SKSEVR 2.0.12. One real 3.5.2 save per qualified SE/AE runtime and one real 3.5.1 VR fixture passed bounded converted-copy acceptance; older versions remain format-gated, not separately tested. The VR fixture covered six facts/task-history caches, task recovery/progression, a roughly 39-minute sampled soak and one cold reload, not populated gossip or stored-name migration. All 66 cold cache comparisons matched; 76/77 state fields matched, with a small scalar deadline difference and unexplained SkyrimNet timeline differences. Three actor mappings were absent before and after; original SkyrimNet database restoration and the native name index remain unqualified. This is not general old-save or full VR qualification.
- Skyrim 1.5.97 / SKSE64 2.0.20 conversion: untested. Adds fix-only eligibility with synthetic coverage only, no live conversion test.
- Preserve non-cache values, including BEL-bearing task destinations and names, byte-for-byte without decoding or re-encoding. Only rendered-cache values are rewritten. A recognized PapyrusUtil owner without STRV can produce a verified unchanged cache-free pair; unknown record types/versions refuse. Expert 1.5.97 and VR conversion remain refused without a qualified historical provider.
- Convert before loading an old save: an unconverted VR copy recovered/progressed its Travel task but showed empty/header-only original facts caches and empty rendered histories despite some raw history remaining. An earlier process crashed with cause unproven; the evidence does not establish that it read the unconverted pair.
- Offline checks passed: both preserved original pairs reproduced their verified converted co-saves byte-for-byte through the production fix entry with a no-game test predicate; original ESS and source metadata remained unchanged. Real Inja/production-codec smoke passed on all three templates, including legacy percent substitutions and encoded literal preservation. The shipped CLI succeeded on a fresh scratch copy with Skyrim closed, preserving original and ESS bytes; it also correctly refused while Skyrim was running. Migration/codec, refusal, backup-locking, incomplete-publication and Unicode/single-file launcher checks passed.
- Historical writer provenance cannot be proved from the file. BEL-to-space is an owner policy, not independently established original text.
- Fix-mode backup covers only the save pair. Rollback also requires matching old providers and corresponding IntelEngine/SkyrimNet external-data backups; do not mix or repeat conversion, load an incomplete output pair, or expect recovery of lost names/history.

### Papyrus API and array guards
- Align the Papyrus API with seven existing native functions; no new native implementation or compatibility aliases.
- Replace one Core and two Schedule array-null comparisons with boolean guards, preserving initialization, length validation, restored state, recovery and monitoring.

### Verification and support
- Tested on official SkyrimNet Beta 28 on Skyrim 1.6.1170 and 1.7.104.
- Skyrim SE 1.5.x: untested.
- Verified on Skyrim 1.6.1170 and 1.7.104 from a fresh new game: caches, stored RNE names and on-screen names survive warm and independent cold reloads; repaired scripts compile and disassemble cleanly, and maintenance and populated-schedule retention were exercised across save/reload. On 1.7.104, on-screen names can take a moment to reappear after loading.
- Legacy migration verified on one real Skyrim 1.6.1170 save: 28/28 sampled surviving caches exact, plus fresh caches through warm and independent cold reloads. Temporary-actor names preserved byte-for-byte, not live-verified. One bounded 1.7.104 converted-copy acceptance retained 11 sampled caches, two owner-policy fields and 24 qualified live names through warm and independent cold reloads; four other name holders remain unverified. Never load a converted save with 3.5.2 or earlier. See [converter procedure and limits](docs/DLL_API.md#offline-legacy-save-conversion).

## v3.5.2 — 2026-10-09

### Skyrim compatibility update
- Uses the pinned MinLL/CommonLibVR native build with the audited non-VR ABI correction.
- Rebuilds with the corrected VS 2022 compiler flags, retaining C++23 without `/O2`, `/std:c++latest`, or `/d2ReducedOptimizeHugeFunctions`.
- Includes the freshly compiled Papyrus scripts and rebuilt dashboard in the full package.
- Verified on Skyrim 1.6.1170; Epicrob confirmed success on his affected 1.7.x setup.
- Requires SkyrimNet Beta 25 or newer and matching SKSE/Address Library; VR is not supported by this build.
- Release/package version is 3.5.2; the tested native DLL remains byte-identical and reports 3.5.1.
- Papyrus/translation backlog fixes and the 1.5.97 crash report on the original IntelEngine repo remain outside this release.

## v3.5.1 — 2026-09-12

### SkyrimNet Beta 25 migration
- Moved IntelEngine's 11 executable actions and three category containers into the `galanx.intelengine` external content bundle.
- Moved four custom prompts and seven character-bio submodules into the same external bundle.
- Preserved all action names, Papyrus mappings, category IDs, and prompt lookup names.
- Removed the retired loose `config/actions` and `prompts` copies to prevent duplicate registration.
- Updated the native dashboard to enumerate and toggle actions in the external bundle.
- Preserved `config/plugins/IntelEngine` separately so plugin settings and user-managed faction configuration continue to work.
- Requires SkyrimNet Beta 25 or newer.

## v3.2.1 — 2026-04-06

### Fix: Stuck tick watchdog (C++ DLL)
- **Politics, NPC interactions, and Story DM** could permanently stop ticking if an LLM callback was lost (SkyrimNet crash, save reload mid-request, etc.)
- Added C++ watchdog system that tracks pending state in the DLL — since the DLL loads fresh every game start, stale flags from saves are automatically detected and reset
- Timeouts: 1 game-hour for politics/NPC ticks, 6 game-hours for story DM (which legitimately runs for hours)
- Works on existing saves without ReSaver — no manual intervention needed

### Improvement: Political director faction dropdowns
- Replaced text inputs with dropdown selectors for faction A and faction B in the political event director
- Dropdown shows all factions from `factions.yaml` with display name and ID
- Prevents silent failures from typos in faction IDs

### Fix: JSON escaping for non-ASCII names
- Rewrote `EscapeJsonString` to properly handle UTF-8 multibyte characters (Cyrillic, CJK, etc.)
- Non-ASCII characters are now emitted as `\uXXXX` JSON escapes, preventing broken JSON when NPC names contain special characters
- Applied consistently across NPC index and dashboard JSON builders

## v3.0.0 — 2026-03-22

### New: Faction Politics System
- **9 configurable factions** — Imperial Legion, Stormcloaks, Thalmor, Companions, Thieves Guild, College of Winterhold, Dark Brotherhood, Silver-Blood Family, Black-Briar Family
- **Political DM** — AI-driven faction events every 6 game hours: trade deals, espionage, sabotage, assassinations, border skirmishes, war declarations, surrenders
- **Gradual escalation** — relations progress naturally from neutral to tense to hostile to war
- **War system** — formal declarations, army strength, morale tracking, off-screen battles, surrender conditions
- **Player standing** — per-faction reputation based on actions, crime, and battle participation
- **Political awareness** — NPCs know about recent political events and react in conversation
- **Configurable** — edit `factions.yaml` to add custom factions, change thresholds, set conflict styles
- **Per-playthrough SQLite database** — all saves in a playthrough share one political timeline; loading an earlier save removes later history and re-opens later-ended wars

### New: Battle System
- **Player-present battles** with 5 waves of spawned soldiers (up to 22 per side)
- **Pending battles** — spawn at real world locations, player must travel within 3 game hours or battle resolves off-screen
- **Mid-battle join** — arrive late to find a battle already in progress with casualties
- **Morale system** — battle ends when one side's morale drops below 20%
- **Standing rewards** — fight for your faction to gain reputation, spectate and lose it
- **Battle witness memories** — nearby NPCs remember the battle and who fought
- **Bounty immunity** — no bounty during faction quests, friendly fire forgiven via battle faction membership
- **Deferred cleanup** — dead soldiers cleaned up behind the player as they walk away

### New: Faction Quests
- **faction_combat** — clear enemy faction soldiers from a location
- **faction_rescue** — rescue a captive from enemy faction soldiers
- **faction_battle** — join a full-scale battle that affects war outcomes
- **Standing-gated** — faction quests appear when standing is 20+ with a faction
- **Faction couriers** — local guards/soldiers deliver the call to arms
- **Enemy validation** — fuzzy matching for LLM-suggested faction names

### New: Prisma UI Dashboard
- **Politics tab** — faction relations grid, active wars, player standings, recent events
- **Director: NPC Social** — manually trigger interactions and gossip between two NPCs
- **Per-action confirmation toggles** — disabled / followers only / everyone
- **Whitelist/blocklist settings** — faction, location, and NPC filters visible and editable
- **Action categories** — drill-down nested actions (Travel, Communication, Scheduling)
- Open with **Shift+7** (customizable hotkey)

### New: Story DM Improvements
- **Player familiarity** — stranger / aware / acquainted tiers based on dialogue and memory history
- **Gossip location context** — NPCs only relay gossip from their own hold
- **Quest subtype tracking** — different quest types don't block each other
- **Anti-duplication** — won't recreate vanilla quests (Amren's sword, etc.)
- **World silence detection** — actively dispatches after 2+ days of quiet

### New: Political DM
- Dedicated AI prompt governing faction relations independently
- War behavior with battle results, morale, surrender
- Conflict styles per faction type (military, guild, political)
- Critical status enforcement — war declaration mandatory at threshold

### Improvements
- Separate Story DM and NPC DM dispatch tracking
- Hold restriction "same town" policies
- GoToLocation blocked during fetch/escort/search tasks
- 100+ new C++ native functions
- Location resolution improvements for small settlements

### Bug Fixes
- Fixed FormID overflow for dynamically spawned actors
- Fixed standing wiped on save/load
- Fixed wrong enemy faction spawning in battles
- Fixed double quest completion
- Fixed guards attacking player during battle
- Fixed gossip without location context
- Fixed `[WAR]` tag showing without active war

---

## v0.9.1 — 2026-02-19

### Bug Fixes

- **Breezehome pathfinding bug**: Fixed NPCs being unable to navigate to Breezehome. The word "home" inside "Breezehome" was incorrectly triggering the home-resolution semantic intent, causing the location resolver to look for a home owner instead of the actual location. Added word boundary detection so compound names like "Breezehome" resolve correctly, while "go home" and "Carlotta's home" still work as expected. Also added exterior door fallback (Strategy 1b) for interior destinations without a world location marker.

- **MCM Story settings not saving**: Fixed Story Engine MCM settings (tick interval, enabled types) resetting to defaults after reloading a save. The scheduler now properly restarts with updated settings when changed via MCM, and settings persist correctly across save/load cycles.

- **Trespassing bug**: Fixed NPCs saying "you need to leave now" even when they personally led the player to their home. Root cause was anti-trespass state being restored prematurely when multiple NPCs shared the same destination cell. Added reference counting in C++ so the cell stays public until ALL visiting NPCs have departed, and added a player-in-cell guard in Papyrus so the cell is never restored to private while the player is still inside.

### Improvements

- **Enhanced Dungeon Master prompts**: Rewrote both the Story DM and NPC Social Life DM prompts with clear, structured instructions. The DM now evaluates each candidate's personality, class, faction allegiance, and profession before dispatching. A temple priest won't abandon their duties without a life-or-death reason, a Stormcloak sympathizer avoids Imperial territory, a timid farmer won't track someone into a Nordic ruin. Story dispatches are grounded in each NPC's recent memories and existing story threads rather than random selection.
