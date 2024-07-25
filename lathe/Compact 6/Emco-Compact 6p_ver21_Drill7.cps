/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  FANUC Lathe post processor configuration.

  $Revision: 41101 83e7ca8cb48dee1f934acaea92a94a09026b1c7f $
  $Date: 2016-06-27 13:25:49 $
  
  FORKID {88B77760-269E-4d46-8588-30814E7FE9A1}
*/

description = "Generic FANUC Turning modified for Emco Compact 6p";
vendor = "Emco";
vendorUrl = "http://www.fanuc.com";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic turning post for FANUC modified for Emco Compact 6P. Use the property 'type' to switch the FANUC mode A, B, and C. The default mode is A.";

extension = "nc";
programNameIsInteger = true;
setCodePage("ascii");

capabilities = CAPABILITY_MILLING | CAPABILITY_TURNING;//capabilities = CAPABILITY_TURNING; //HMR for drilling
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  writeMachine: true, // (changed from false) write machine
  writeTools: true, // writes the tools
  feedScale: 1000, //Scaling for Emco when using feed in um/rev instead of default mm/rev with G95
  UnclampChuck: true,// unclamp chuck on end of program  hmr
  preloadTool: false, // preloads next tool on tool change if any
  showSequenceNumbers: true, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 10, // increment for sequence numbers
  optionalStop: false, // optional stop
  o8: false, // specifies 8-digit program number
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  useRadius: false, // (changed from true) specifies that arcs should be output using the radius (R word) instead of the I, J, and K words.
  maximumSpindleSpeed: 100 * 63, // specifies the maximum spindle speed
  machineHomeX: 45, // Home Position X for retract
  // machineHomeY: 12, // Home Position Y for retract
  machineRetractPlane: 190, // Home Position Z for retract, Safe Z to revolve turret (Can be calculated from tool offset and revolver radii (165))
  type: "B", // specifies the type A, B, C Was A trying B now hmr
  useParametricFeed: false, // specifies that feed should be output using Q values
  showNotes: true // specifies that operation notes should be output.
};



var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-";
// Format N according to manual
var nFormat = createFormat({prefix:"", width:4, zeropad:true, decimals:1});

// var gFormat = createFormat({prefix:"G", decimals:1});
//var mFormat = createFormat({prefix:"M", decimals:1});
var gFormat = createFormat({prefix:"G", width:2, zeropad:true, decimals:1});
var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:1});
var spatialFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var xFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true, scale:2}); // diameter mode
var yFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var zFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var dFormat = createFormat({prefix:"D", width:2, zeropad:true, decimals:1}); //added, might be used for canned cycles
var myFormat = createFormat({decimals:0, forceDecimal:true}); //added, might be used for 1/1000 outputs
var rFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true}); // radius
var feedFormat = createFormat({decimals:(unit == MM ? 4 : 5), forceDecimal:true});
// var toolFormat = createFormat({decimals:0, width:4, zeropad:true});
var toolFormat = createFormat({width:2, zeropad:true, decimals:1});
var rpmFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-99999.999
var milliFormat = createFormat({decimals:0}); // milliseconds // range 1-9999
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xFormat);
var yOutput = createVariable({prefix:"Y"}, yFormat);
var zOutput = createVariable({prefix:"Z"}, zFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);
var dOutput = createVariable({prefix:"D"}, dFormat);
var myOutput = createVariable({prefix:"D"}, myFormat);
// Debug https://forums.autodesk.com/t5/hsm-post-processor-forum/debug-in-post/td-p/6077595#msg1692
var deBugPost = 0; // Turn post debugging off(0) or on(1) 

// circular output
// var kOutput = createReferenceVariable({prefix:"K"}, xFormat);
var kOutput = createReferenceVariable({prefix:"K", force:true}, xFormat);
// var iOutput = createReferenceVariable({prefix:"I"}, xFormat); // no scaling
var iOutput = createReferenceVariable({prefix:"I", force:true}, xFormat); // no scaling

var g92ROutput = createVariable({prefix:"R"}, zFormat); // no scaling

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91 // only for B and C mode
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G98-99 / G94-95
var gSpindleModeModal = createModal({}, gFormat); // modal group 5 // G96-97
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal = createModal({}, gFormat); // modal group 10 // G98-99

// fixed settings
var firstFeedParameter = 500;
var gotSecondarySpindle = false;//hmr
var gotPartCatcher = true;//hmr

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;
var optionalSection = false;
var forceSpindleSpeed = false;
var activeMovements; // do not use by default
var currentFeedId;
var threadStart = 0; // Used by threadturning


/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    if (optionalSection) {
      var text = formatWords(arguments);
      if (text) {
//        writeWords("/", "N" + sequenceNumber, text);
        writeWords("/", "N" + nFormat.format(sequenceNumber) + " ", text);
      }
    } else {
//      writeWords2("N" + sequenceNumber, arguments);
      writeWords2("N" + nFormat.format(sequenceNumber) + " ", arguments);
    }
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    if (optionalSection) {
      writeWords2("/", arguments);
    } else {
      writeWords(arguments);
    }
  }
}

/**
  Writes the specified optional block.
*/
function writeOptionalBlock() {
  if (properties.showSequenceNumbers) {
    var words = formatWords(arguments);
    if (words) {
//      writeWords("/", "N" + sequenceNumber, words);
      writeWords("/", "N" + nFormat.format(sequenceNumber) + " ", words);
      sequenceNumber += properties.sequenceNumberIncrement;
    }
  } else {
    writeWords2("/", arguments);
  }
}

function formatComment(text) {
  return "(" + filterText(String(text).toUpperCase(), permittedCommentChars).replace(/[\(\)]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
  //writeln(formatComment(text));
  writeBlock(formatComment(text));
}
/** 
 https://forums.autodesk.com/t5/hsm-post-processor-forum/debug-in-post/td-p/6077595#msg1692
 Turn Post De-bugging On/Off
*/
 if (deBugPost == 1) { 
   setWriteInvocations(true); // tells which entry functions are called
   setWriteStack(true); // tells which functions are called for each NC block
 }

function onOpen() {

  yOutput.disable();

  if (!(properties.type in {"A":0, "B":0, "C":0})) {
    error(localize("Unsupported type. Only A, B, and C are allowed."));
    return;
  }
  
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
//  writeln("%"); //added inline below

  if (programName) {
    var programId;
    try {
      programId = getAsInt(programName);
    } catch(e) {
      error(localize("Program name must be a number."));
      return;
    }
    if (properties.o8) {
      if (!((programId >= 1) && (programId <= 99999999))) {
        error(localize("Program number is out of range."));
        return;
      }
    } else {
      if (!((programId >= 1) && (programId <= 9999))) {
        error(localize("Program number is out of range."));
        return;
      }
    }
    if ((programId >= 8000) && (programId <= 9999)) {
      warning(localize("Program number is reserved by tool builder."));
    }
    var oFormat = createFormat({width:(properties.o8 ? 8 : 4), zeropad:true, decimals:0});
    if (programComment) {
//      writeln("O" + oFormat.format(programId) + " (" + filterText(String(programComment).toUpperCase(), permittedCommentChars) + ")");
      writeln("%O" + oFormat.format(programId) + " (" + filterText(String(programComment).toUpperCase(), permittedCommentChars) + ")");
    } else {
//      writeln("O" + oFormat.format(programId));
      writeln("%O" + oFormat.format(programId) + " ");
    }
  } else {
    error(localize("Program name has not been specified."));
    return;
  }
  // Create or add parameters to MachineConfiguration
  machineConfiguration.setHomePositionX(properties.machineHomeX);// Might want to use toPreciseUnit(-29.0, IN)
  // machineConfiguration.setHomePositionY(properties.machineHomeY);
  machineConfiguration.setRetractPlane(properties.machineRetractPlane);
  if (deBugPost == 1) {
    writeWords(machineConfiguration.getXML());
  } 
  
  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // dump tool information (copied from generic milling fanuc post)
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + toolFormat.format(tool.lengthOffset) + " " +
          "D=" + zFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + zFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + zFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }
  
  if (false) {
    // check for duplicate tool number
    for (var i = 0; i < getNumberOfSections(); ++i) {
      var sectioni = getSection(i);
      var tooli = sectioni.getTool();
      for (var j = i + 1; j < getNumberOfSections(); ++j) {
        var sectionj = getSection(j);
        var toolj = sectionj.getTool();
        if (tooli.number == toolj.number) {
          if (zFormat.areDifferent(tooli.diameter, toolj.diameter) ||
              zFormat.areDifferent(tooli.cornerRadius, toolj.cornerRadius) ||
              abcFormat.areDifferent(tooli.taperAngle, toolj.taperAngle) ||
              (tooli.numberOfFlutes != toolj.numberOfFlutes)) {
            error(
              subst(
                localize("Using the same tool number for different cutter geometry for operation '%1' and '%2'."),
                sectioni.hasParameter("operation-comment") ? sectioni.getParameter("operation-comment") : ("#" + (i + 1)),
                sectionj.hasParameter("operation-comment") ? sectionj.getParameter("operation-comment") : ("#" + (j + 1))
              )
            );
            return;
          }
        }
      }
    }
  }
  // absolute coordinates and feed per min
  if (properties.type == "A") {
    writeBlock(gFeedModeModal.format(98), gPlaneModal.format(18));
  } else {
//    writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(95), gPlaneModal.format(18));
//    writeBlock(gFeedModeModal.format(95)); Bug? see page 39 in Fanuc 0 Lathe Operator Manual 61394e document
    gPlaneModal.format(18)
    writeBlock(gFeedModeModal.format(94));
  }

  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(70)); //was 20
    break;
  case MM:
    writeBlock(gUnitModal.format(71)); //was 21
    break;
  }

  if (properties.type == "A") {
    writeBlock(gFormat.format(50), sOutput.format(properties.maximumSpindleSpeed));
  } else {
    writeBlock(gFormat.format(92), sOutput.format(properties.maximumSpindleSpeed));
  }

  onCommand(COMMAND_START_CHIP_TRANSPORT);
}

function onComment(message) {
  var comments = String(message).split(";");
  for (comment in comments) {
    writeComment(comments[comment]);
  }
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

function forceFeed() {
  currentFeedId = undefined;
  feedOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  forceFeed();
}

function FeedContext(id, description, feed) {
  this.id = id;
  this.description = description;
  this.feed = feed;
}

function getFeed(f) {
	// writeComment(["Entering getFeed " , conditional(currentSection.feedMode == FEED_PER_REVOLUTION, "FEED_PER_REVOLUTION is true")])
  if (activeMovements) {
    var feedContext = activeMovements[movement];
    if (feedContext != undefined) {
      if (!feedFormat.areDifferent(feedContext.feed, f)) {
        if (feedContext.id == currentFeedId) {
          return ""; // nothing has changed
        }
		// Add functionality for scaling when doing um/rev
		writeComment(["DANGER, Entering forceFeed from getFeed. firstFeedParameter is ", firstFeedParameter  , conditional(currentSection.feedMode == FEED_PER_REVOLUTION, "FEED_PER_REVOLUTION is true")])
        forceFeed();
        currentFeedId = feedContext.id;
        return "F#" + (firstFeedParameter + feedContext.id);
      }
    }
    currentFeedId = undefined; // force Q feed next time
  }
  // writeComment(["Returning ", f ,"from getFeed due to no activeMovements " , conditional(currentSection.feedMode == FEED_PER_REVOLUTION, "FEED_PER_REVOLUTION is true")])
  if (currentSection.feedMode == FEED_PER_REVOLUTION){
	return feedOutput.format(f*properties.feedScale); // use feed value * scaling
  } else {
    return feedOutput.format(f); // use feed value	  
  }
}

function initializeActiveFeeds() {
  activeMovements = new Array();
  var movements = currentSection.getMovements();
  
  var id = 0;
  var activeFeeds = new Array();
  if (hasParameter("operation:tool_feedCutting")) {
    if (movements & ((1 << MOVEMENT_CUTTING) | (1 << MOVEMENT_LINK_TRANSITION) | (1 << MOVEMENT_EXTENDED))) {
      var feedContext = new FeedContext(id, localize("Cutting"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedCuttingRel") : getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_CUTTING] = feedContext;
      activeMovements[MOVEMENT_LINK_TRANSITION] = feedContext;
      activeMovements[MOVEMENT_EXTENDED] = feedContext;
    }
    ++id;
    if (movements & (1 << MOVEMENT_PREDRILL)) {
      feedContext = new FeedContext(id, localize("Predrilling"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedCuttingRel") : getParameter("operation:tool_feedCutting"));
      activeMovements[MOVEMENT_PREDRILL] = feedContext;
      activeFeeds.push(feedContext);
    }
    ++id;
  }
  
  if (hasParameter("operation:finishFeedrate")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:finishFeedrateRel") : getParameter("operation:finishFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  } else if (hasParameter("operation:tool_feedCutting")) {
    if (movements & (1 << MOVEMENT_FINISH_CUTTING)) {
      var feedContext = new FeedContext(id, localize("Finish"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedCuttingRel") : getParameter("operation:tool_feedCutting"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_FINISH_CUTTING] = feedContext;
    }
    ++id;
  }
  
  if (hasParameter("operation:tool_feedEntry")) {
    if (movements & (1 << MOVEMENT_LEAD_IN)) {
      var feedContext = new FeedContext(id, localize("Entry"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedEntryRel") : getParameter("operation:tool_feedEntry"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_IN] = feedContext;
    }
    ++id;
  }

  if (hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LEAD_OUT)) {
      var feedContext = new FeedContext(id, localize("Exit"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedExitRel") : getParameter("operation:tool_feedExit"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LEAD_OUT] = feedContext;
    }
    ++id;
  }

  if (hasParameter("operation:noEngagementFeedrate")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(id, localize("Direct"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:noEngagementFeedrateRel") : getParameter("operation:noEngagementFeedrate")); 
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  } else if (hasParameter("operation:tool_feedCutting") &&
             hasParameter("operation:tool_feedEntry") &&
             hasParameter("operation:tool_feedExit")) {
    if (movements & (1 << MOVEMENT_LINK_DIRECT)) {
      var feedContext = new FeedContext(
        id,
        localize("Direct"),
        Math.max(
          (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedCuttingRel") : getParameter("operation:tool_feedCutting"),
          (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedEntryRel") : getParameter("operation:tool_feedEntry"),
          (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedExitRel") : getParameter("operation:tool_feedExit")
        )
      );
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_LINK_DIRECT] = feedContext;
    }
    ++id;
  }
  
  if (hasParameter("operation:reducedFeedrate")) {
    if (movements & (1 << MOVEMENT_REDUCED)) {
      var feedContext = new FeedContext(id, localize("Reduced"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:reducedFeedrateRel") : getParameter("operation:reducedFeedrate"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_REDUCED] = feedContext;
    }
    ++id;
  }

  if (hasParameter("operation:tool_feedRamp")) {
    if (movements & ((1 << MOVEMENT_RAMP) | (1 << MOVEMENT_RAMP_HELIX) | (1 << MOVEMENT_RAMP_PROFILE) | (1 << MOVEMENT_RAMP_ZIG_ZAG))) {
      var feedContext = new FeedContext(id, localize("Ramping"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedRampRel") : getParameter("operation:tool_feedRamp"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_RAMP] = feedContext;
      activeMovements[MOVEMENT_RAMP_HELIX] = feedContext;
      activeMovements[MOVEMENT_RAMP_PROFILE] = feedContext;
      activeMovements[MOVEMENT_RAMP_ZIG_ZAG] = feedContext;
    }
    ++id;
  }
  if (hasParameter("operation:tool_feedPlunge")) {
    if (movements & (1 << MOVEMENT_PLUNGE)) {
      var feedContext = new FeedContext(id, localize("Plunge"), (currentSection.feedMode == FEED_PER_REVOLUTION) ? getParameter("operation:tool_feedPlungeRel") : getParameter("operation:tool_feedPlunge"));
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_PLUNGE] = feedContext;
    }
    ++id;
  }
  if (true) { // high feed
    if (movements & (1 << MOVEMENT_HIGH_FEED)) {
      var feedContext = new FeedContext(id, localize("High Feed"), this.highFeedrate);
      activeFeeds.push(feedContext);
      activeMovements[MOVEMENT_HIGH_FEED] = feedContext;
    }
    ++id;
  }
  
  for (var i = 0; i < activeFeeds.length; ++i) {
    var feedContext = activeFeeds[i];
    writeBlock("#" + (firstFeedParameter + feedContext.id) + "=" + feedFormat.format(feedContext.feed), formatComment(feedContext.description));
  }
}

function getSpindle() {
  if (getNumberOfSections() == 0) {
    return SPINDLE_PRIMARY;
  }
  if (getCurrentSectionId() < 0) {
    return getSection(getNumberOfSections() - 1).spindle == 0;
  }
  if (currentSection.getType() == TYPE_TURNING) {
    return currentSection.spindle;
  } else {
    if (isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1))) {
      return SPINDLE_PRIMARY;
    } else if (isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, -1))) {
      if (!gotSecondarySpindle) {
        error(localize("Secondary spindle is not available."));
      }
      return SPINDLE_SECONDARY;
    } else {
      return SPINDLE_PRIMARY;
    }
  }
}

function onSection() {
  if (currentSection.getType() != TYPE_TURNING) {
    if (!hasParameter("operation-strategy") || (getParameter("operation-strategy") != "drill")) {
      if (currentSection.getType() == TYPE_MILLING) {
        error(localize("Milling toolpath is not supported."));
      } else {
        error(localize("Non-turning toolpath is not supported."));
      }
      return;
    }
  }

  var forceToolAndRetract = optionalSection && !currentSection.isOptional();
  optionalSection = currentSection.isOptional();

  var turning = (currentSection.getType() == TYPE_TURNING);
  
  var insertToolCall = forceToolAndRetract || isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newSpindle = isFirstSection() ||
    (getPreviousSection().spindle != currentSection.spindle);
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  if (insertToolCall || newSpindle || newWorkOffset) {
    // retract to safe plane
	forceXYZ();
  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
	  if (deBugPost == 1) {
        writeWords("(Entering onClose and machine has not Home");
      } 
    writeBlock(gFormat.format(28), "U" + xFormat.format(0), conditional(yOutput.isEnabled(), "V" + yFormat.format(0)), "W" + zFormat.format(0)); // return to home
  } else {
    var homeX;
    if (machineConfiguration.hasHomePositionX()) {
      homeX = xOutput.format(machineConfiguration.getHomePositionX());
    }
    var homeY;
    if (yOutput.isEnabled() && machineConfiguration.hasHomePositionY()) {
      homeY = yOutput.format(machineConfiguration.getHomePositionY());
    }
    if (properties.type == "A") {
      writeBlock(gFormat.format(53), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane()));
    } else {
      if (deBugPost == 1) {
        writeComment("(Entering onClose and machine has Home of X or Y(Z)");
      } 
//      writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane()));
      writeBlock("T" + toolFormat.format(0) + toolFormat.format(0)); //This will cancel any tooloffsets in preparation for move to home
      writeBlock(gFormat.format(53),gFormat.format(56), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane())); // Retract to home position
    }
  }
    retracted = true;
	writeComment("retracted = true, did we do something clever?");
//    writeBlock(gFormat.format(28), "U" + xFormat.format(0)); // retract
// Do we need to do something here to make safe tool change?
// If so , reset WO(G53 G56) and TO (T0000) and retract to known good position...
// Note: In order to be able to carry out the tool change manually, an intermediate
// stop with M00 must be programmed before the T statement.
// With T0000 the selected tool dimensions are canceled and the tool selected is deselected.
    forceXYZ();
  }

  //writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
  
  if (properties.showNotes && hasParameter("notes")) {
    var notes = getParameter("notes");
    if (notes) {
      var lines = String(notes).split("\n");
      var r1 = new RegExp("^[\\s]+", "g");
      var r2 = new RegExp("[\\s]+$", "g");
      for (line in lines) {
        var comment = lines[line].replace(r1, "").replace(r2, "");
        if (comment) {
          writeComment(comment);
        }
      }
    }
  }
  
  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF); // was commented
  
    if (!isFirstSection() && properties.optionalStop) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }

    var compensationOffset = tool.isTurningTool() ? tool.compensationOffset : tool.lengthOffset;
    if (compensationOffset > 99) {
      error(localize("Compensation offset is out of range."));
      return;
    }
 //   writeBlock("T" + toolFormat.format(tool.number * 100 + compensationOffset));
 //   writeBlock("T" + toolFormat.format(tool.number) + toolFormat.format(tool.lengthOffset));
    writeBlock("T" + toolFormat.format(tool.number) + toolFormat.format(compensationOffset)); 
 if (tool.comment) {
      writeComment(tool.comment);
    }

    if (properties.preloadTool) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        var compensationOffset = nextTool.isTurningTool() ? nextTool.compensationOffset : nextTool.lengthOffset;
        if (compensationOffset > 99) {
          error(localize("Compensation offset is out of range."));
          return;
        }
        writeBlock("T" + toolFormat.format(nextTool.number * 100 + compensationOffset));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstTool = section.getTool().number;
        if (tool.number != firstTool.number) {
          var compensationOffset = firstTool.isTurningTool() ? firstTool.compensationOffset : firstTool.lengthOffset;
          if (compensationOffset > 99) {
            error(localize("Compensation offset is out of range."));
            return;
          }
          writeBlock("T" + toolFormat.format(firstTool.number * 100 + compensationOffset));
        }
      }
    }
  }

  // wcs
  if (insertToolCall) { // force work offset when changing tool
    currentWorkOffset = undefined;
  }
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var p = workOffset - 6; // 1->...
      if (p > 300) {
        error(localize("Work offset out of range."));
        return;
      } else {
        if (workOffset != currentWorkOffset) {
          writeBlock(gFormat.format(54.1), "P" + p); // G54.1P
          currentWorkOffset = workOffset;
        }
      }
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }

  // set coolant after we have positioned at Z
  setCoolant(tool.coolant);

  forceAny();
  gMotionModal.reset();

  gFeedModeModal.reset();
  if (currentSection.feedMode == FEED_PER_REVOLUTION) {
    writeBlock(gFeedModeModal.format((properties.type == "A") ? 99 : 95));
  } else {
    writeBlock(gFeedModeModal.format((properties.type == "A") ? 98 : 94));
  }

  // writeBlock(mFormat.format(currentSection.tailstock ? x : x));
  // writeBlock(mFormat.format(clampPrimaryChuck ? x : x));
  // writeBlock(mFormat.format(clampSecondaryChuck ? x : x));

  var mSpindle = tool.clockwise ? 3 : 4;
  /*
  switch (currentSection.spindle) {
  case SPINDLE_PRIMARY:
    mSpindle = tool.clockwise ? 3 : 4;
    break;
  case SPINDLE_SECONDARY:
    mSpindle = tool.clockwise ? 143 : 144;
    break;
  }
  */
  
  gSpindleModeModal.reset();
  if (currentSection.getTool().getSpindleMode() == SPINDLE_CONSTANT_SURFACE_SPEED) {
    var maximumSpindleSpeed = (tool.maximumSpindleSpeed > 0) ? Math.min(tool.maximumSpindleSpeed, properties.maximumSpindleSpeed) : properties.maximumSpindleSpeed;
    if (properties.type == "A") {
      writeBlock(gFormat.format(50), sOutput.format(maximumSpindleSpeed));
    } else {
      writeBlock(gFormat.format(92), sOutput.format(maximumSpindleSpeed));
    }
    writeBlock(gSpindleModeModal.format(96), sOutput.format(tool.surfaceSpeed * ((unit == MM) ? 1/1000.0 : 1/12.0)), mFormat.format(mSpindle));
  } else {
    writeBlock(gSpindleModeModal.format(97), sOutput.format(tool.spindleRPM), mFormat.format(mSpindle));
  }
  
  setRotation(currentSection.workPlane);

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    // TAG: need to retract along X or Z
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    }
  }

  if (insertToolCall) {
    gMotionModal.reset();
    
    if (properties.type == "A") {
      writeBlock(gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z)
      );
    } else {
//      writeBlock(
//        gAbsIncModal.format(90),
//        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z)
      writeBlock(
        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z)
      );
    }

    gMotionModal.reset();
  }

  if (gotPartCatcher &&
      (currentSection.partCatcher ||
       (typeof currentSection.partCatcher == "undefined") &&
       hasParameter("operation-strategy") &&
       (getParameter("operation-strategy") == "turningPart"))) {
        writeBlock(mFormat.format(24));
    // activate part catcher here
  }

  if (properties.useParametricFeed &&
      hasParameter("operation-strategy") &&
      (getParameter("operation-strategy") != "drill")) {
    if (!insertToolCall &&
        activeMovements &&
        (getCurrentSectionId() > 0) &&
        (getPreviousSection().getPatternId() == currentSection.getPatternId())) {
      // use the current feeds
    } else {
      initializeActiveFeeds();
    }
  } else {
    activeMovements = undefined;
  }

  if (insertToolCall || retracted) {
    gPlaneModal.reset();
  }
}

function onDwell(seconds) {
//  if (seconds > 99999.999) {
    if (seconds > 1000) {
    warning(localize("Dwelling time is out of range."));
  }
  //milliseconds = clamp(1, seconds * 1000, 99999999);
  tenthseconds = clamp(1, seconds * 10, 10000);
  //writeBlock(/*gFeedModeModal.format(94),*/ gFormat.format(4), "P" + milliFormat.format(milliseconds));
  writeBlock(/*gFeedModeModal.format(94),*/ gFormat.format(4), "D4=" + milliFormat.format(tenthseconds));
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gMotionModal.format(0), gFormat.format(41), x, y, z);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gMotionModal.format(0), gFormat.format(42), x, y, z);
        break;
      default:
        writeBlock(gMotionModal.format(0), gFormat.format(40), x, y, z);
      }
    } else {
      writeBlock(gMotionModal.format(0), x, y, z);
    }
    forceFeed();
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = getFeed(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      //writeBlock(gPlaneModal.format(18));
      gPlaneModal.format(18)
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gMotionModal.format(1), gFormat.format(41), x, y, z, f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gMotionModal.format(1), gFormat.format(42), x, y, z, f);
        break;
      default:
        writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      forceFeed(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (isSpeedFeedSynchronizationActive()) {
    error(localize("Speed-feed synchronization is not supported for circular moves."));
    return;
  }
  
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (properties.useRadius || isHelical()) { // radius mode does not support full arcs
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), getFeed(feed));
      gPlaneModal.format(17)
      writeBlock(conditional(properties.type != "A", ""), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), getFeed(feed));
      break;
    case PLANE_ZX:
      //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      gPlaneModal.format(18)
      writeBlock(conditional(properties.type != "A", ""), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      break;
    case PLANE_YZ:
      //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      gPlaneModal.format(19)
      writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else if (!properties.useRadius) {
    switch (getCircularPlane()) {
    case PLANE_XY:
      //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), getFeed(feed));
      gPlaneModal.format(17)
      writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), getFeed(feed));
      break;
    case PLANE_ZX:
    //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
    gPlaneModal.format(18)      
    writeBlock(conditional(properties.type != "A", ""), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      break;
    case PLANE_YZ:
      //writeBlock(conditional(properties.type != "A", gAbsIncModal.format(90)), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      gPlaneModal.format(19)
      writeBlock(conditional(properties.type != "A", ""), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), getFeed(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else { // use radius mode
    var r = getCircularRadius();
    if (toDeg(getCircularSweep()) > (180 + 1e-9)) {
      r = -r; // allow up to <360 deg arcs
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      //writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      gPlaneModal.format(17)
      writeBlock(gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      break;
    case PLANE_ZX:
      //writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      gPlaneModal.format(18)
      writeBlock(gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      break;
    case PLANE_YZ:
      //writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      gPlaneModal.format(19)
      writeBlock(gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), "R" + rFormat.format(r), getFeed(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

function onCycle() {
  if (deBugPost == 1) {
      writeComment("cycleType is " + cycleType);
  }}

function getCommonCycle(x, y, z, r) {
  forceXYZ(); // force xyz on first drill hole of any cycle
  return [ xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + spatialFormat.format(r)];//hmr 
}

function getDrillingCycle(z) {
    //forceXYZ(); // force xyz on first drill hole of any cycle
    zOutput.reset();//hmr from alex email
    return [zOutput.format(z)];
     "D3" + [spatialFormat.format(r)];//hmr ]
}
  

function onCyclePoint(x, y, z) {
  if (isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, 1)) ||
      isSameDirection(currentSection.workPlane.forward, new Vector(0, 0, -1))) {
//    writeBlock(gPlaneModal.format(17)); // XY plane Bug?
//    writeBlock(gPlaneModal.format(18)); // XZ plane, G18 not supported by Emco
//    adding below as a test to see if it effects line 1025
     gPlaneModal.format(17) //added as a test to see if it effects line 1085 and below which it did.
  } else {
    expandCyclePoint(x, y, z);
    return;
  }

  switch (cycleType) {
  case "thread-turning":
	var r = -cycle.incrementalX; // positive if taper goes down - delta radius
    var threadsPerInch = 1.0/cycle.pitch; // per mm for metric
    var f = 1/threadsPerInch;

	// if not supported use ( G00(start) G33(thread) G00(clear) G00(clearance) repeat ) as an expanded cycle (not implemented)
	// Only ('operation:infeedMode', 'constant') is supported

    //var codes = {A: 92, B: 78, C: 21};
    /* Original code with G85 change
	var codes = {A: 92, B: 85, C: 21}; //Emco use G85
    writeBlock(
      gMotionModal.format(codes[properties.type]),
      xOutput.format(x - cycle.incrementalX), //cycle.incrementalX seems to be total thread depth
      yOutput.format(y),
      zOutput.format(z),
      conditional(zFormat.isSignificant(r), g92ROutput.format(r)),
      feedOutput.format(f)
    );*/
	if (isFirstCyclePoint()) {
      threadStart = getFramePosition(getCurrentPosition());
	  //writeComment(["ThreadStart.z is ", threadStart.z])
	}
	/*   Some notes about Emco TM01 and TM02
  This post has been made for TM01 and has not been tested with TM02
  Single thread can be programmed with G33, this implementation
  tries to leverage G85 as a canned threading cycle (use cycle checked in CAM)
  TM02 has further parameters for cycles
  NB! for TM02 P2 is in mm TM02 also has a D4 and D7 parameter
  
  For TM01
  G85 X/U .. Z/W .. P0=.. P2=.. D3=.. D5=.. D6=.. F..
  P0 Conical offset in mm (Not tested)
  P2 thread retract length in 1/1000mm
  D3 incrementalDepth per iteration in 1/1000mm
  D5 Thread total included angle in degr
  D6 Total thread depth in 1/1000mm
  F Threadpitch in 1/1000mm (for angles above 45 this is given in X)
  Since Fusion generates initial X including first stepdown we wait until
  last cycle when we know final depth to calculate starting X from there. */
	if (isLastCyclePoint()) {
	  // Feed in to starting point
	  writeBlock(gMotionModal.format(1), xOutput.format(x + 2*getParameter("operation:threadDepth") - cycle.incrementalX), feedOutput.format(getParameter("operation:tool_feedEntry")));

      var codes = {A: 92, B: 85, C: 21}; //Emco use G85
	  // To decide number of stepdowns and spring pass use
	  // operation:threadDepth
	  // operation:numberOfStepdowns
	  // operation:threadPitch
	  // operation:infeedAngle (final pass is correct Z positions no matter what infeed is set)
	  // operation:fadeThreadEnd
	  // operation:nullPass (1=Spring pass)
	  // operation:fadeThreadEnd (This would be used for P2)
	  // incrementalX (This is conical X-shape from threadstart)
	  // incrementalZ (This is total Z-threadlength)
	  writeBlock(
        gMotionModal.format(codes[properties.type]),
        xOutput.format(x), //This works with reduced infeed but not with angles above 45
        yOutput.format(y),
        zOutput.format(z),
		conditional(zFormat.isSignificant(r),"P0=" + zFormat.format(r*1000)),
		conditional((getParameter("operation:fadeThreadEnd") != "0"),"P2=" + zFormat.format(getParameter("operation:fadeThreadEnd")*1000)),
		"D3=" + myFormat.format(getParameter("operation:threadDepth")*1000/getParameter("operation:numberOfStepdowns")),
		conditional(zFormat.isSignificant(getParameter("operation:infeedAngle")),"D5=" + zFormat.format(2*getParameter("operation:infeedAngle"))),
		"D6=" + zFormat.format(getParameter("operation:threadDepth")*1000),
        feedOutput.format(f*1000)
		);
	  // Spring pass
	  if (getParameter("operation:nullPass") >= 1){
		writeComment("springPasses gt 0")
		writeBlock(gMotionModal.format(0), xOutput.format(cycle.clearance), zOutput.format(getCyclePoint(getCyclePointId()).z));
		writeBlock(gMotionModal.format(0), xOutput.format(cycle.clearance), zOutput.format(threadStart.z));
		// Feed in to starting point
	    writeBlock(gMotionModal.format(1), xOutput.format(x + getParameter("operation:threadDepth") - cycle.incrementalX), feedOutput.format(getParameter("operation:tool_feedEntry")));
	  
	    writeBlock(
        gMotionModal.format(codes[properties.type]),
        xOutput.format(x), //This works with reduced infeed but not with angles above 45
        yOutput.format(y),
        zOutput.format(z),
		conditional(zFormat.isSignificant(r),"P0=" + zFormat.format(r*1000)),
		conditional((getParameter("operation:fadeThreadEnd") != "0"),"P2=" + zFormat.format(getParameter("operation:fadeThreadEnd")*1000)),
		"D3=" + zFormat.format(getParameter("operation:threadDepth")*1000),
		conditional(zFormat.isSignificant(getParameter("operation:infeedAngle")),"D5=" + zFormat.format(getParameter("operation:infeedAngle"))),
		"D6=" + zFormat.format(getParameter("operation:threadDepth")*1000),
        feedOutput.format(f*1000)
		);
   	  }
		
	  if (r > z) {
		  //error(localize("Unsupported threading operation."));
	  }
	  
	}
    return;
  }

  if (isFirstCyclePoint()) {
    if (deBugPost == 1) {
        writeComment("gPlaneModal is " + gPlaneModal.getCurrent());
    }
    switch (gPlaneModal.getCurrent()) {
    case 17:
      writeBlock(gMotionModal.format(0), zOutput.format(cycle.clearance));
      break;
    case 18:
      writeBlock(gMotionModal.format(0), yOutput.format(cycle.clearance));
      break;
    case 19:
      writeBlock(gMotionModal.format(0), xOutput.format(cycle.clearance));
      break;
    default:
      error(localize("Unsupported drilling orientation."));
	  // When drilling this is unset for some reason and yields infinity
	  // gPlaneModal must be set to 17 for drilling? Related to onCyclePoint(x, y, z) line 975 ?
	  // Can we set it internally without outputting a block since it´s not supported? yes done,
	  // Maybe this has to be done for all G17 and G18, need to read the manual
      return;
    }

    repositionToCycleClearance(cycle, x, y, z);
    
    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    //var P = (cycle.dwell == 0) ? 0 : clamp(1, cycle.dwell * 1000, 99999999); // in milliseconds
    var P = (cycle.dwell == 0) ? 0 : clamp(1, cycle.dwell * 10, 10000); // in tenths of seconds
    switch (cycleType) {
        // Drilling on Emco T1

    case "drilling":
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(81),
        (properties.type == "A") ? "" : "", conditional(properties.type != "A", ""), gCycleModal.format(87),
        getDrillingCycle(z),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (P > 0) {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(82),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(81),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "chip-breaking":
      // cycle.accumulatedDepth is ignored
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(73),
         // (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(87),//hmr 73
        // (properties.type == "A") ? "" : "", conditional(properties.type != "A", ""), gCycleModal.format(87),//this one wroks
        gCycleModal.format(87),
         getDrillingCycle(z),
         
          // getCommonCycle( x, y, z, cycle.retract),//HMR 
         // "Q" + spatialFormat.format(cycle.incrementalDepth),//HMR
         "D3=" + spatialFormat.format(cycle.incrementalDepth*1000),//HMR added *1000 mas well to mm>um
          feedOutput.format(F)
        );
      }
      break;
    case "deep-drilling":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(83),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(83),
          getCommonCycle(x, y, z, cycle.retract),
          "Q" + spatialFormat.format(cycle.incrementalDepth),
          // conditional(P > 0, "P" + milliFormat.format(P)),
          feedOutput.format(F)
        );
      }
      break;
    case "tapping":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format((tool.type == TOOL_TAP_LEFT_HAND) ? 74 : 84),
        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format((tool.type == TOOL_TAP_LEFT_HAND) ? 74 : 84),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "left-tapping":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(74),
        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(74),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "right-tapping":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(84),
        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(84),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "tapping-with-chip-breaking":
    case "left-tapping-with-chip-breaking":
    case "right-tapping-with-chip-breaking":
      if (!F) {
        F = tool.getTappingFeedrate();
      }
      writeBlock(mFormat.format(29), sOutput.format(tool.spindleRPM));
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format((tool.type == TOOL_TAP_LEFT_HAND ? 74 : 84)),
        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format((tool.type == TOOL_TAP_LEFT_HAND ? 74 : 84)),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P),
        "Q" + spatialFormat.format(cycle.incrementalDepth),
        feedOutput.format(F)
      );
      break;
    case "fine-boring":
      writeBlock(
//        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(76),
        (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(76),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P), // not optional
        "Q" + xFormat.format(cycle.shift),
        feedOutput.format(F)
      );
      break;
    case "reaming":
      if (P > 0) {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(89),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(85),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "stop-boring":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(86),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(86),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "boring":
      if (P > 0) {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(89),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P), // not optional
          feedOutput.format(F)
        );
      } else {
        writeBlock(
//          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", gAbsIncModal.format(90)), gCycleModal.format(85),
          (properties.type == "A") ? "" : gRetractModal.format(98), conditional(properties.type != "A", ""), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      var _x = xOutput.format(x);
      var _y = yOutput.format(y);
      var _z = zOutput.format(z);
      if (!_x && !_y && !_z) {
        switch (gPlaneModal.getCurrent()) {
        case 17: // XY
          xOutput.reset(); // at least one axis is required
          _x = xOutput.format(x);
          break;
        case 18: // ZX
          zOutput.reset(); // at least one axis is required
          _z = zOutput.format(z);
          break;
        case 19: // YZ
          yOutput.reset(); // at least one axis is required
          _y = yOutput.format(y);
          break;
        }
      }
      writeBlock(_x, _y, _z);
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    switch (cycleType) {
    case "thread-turning":
      forceFeed();
      xOutput.reset();
      zOutput.reset();
      g92ROutput.reset();
      break;
    default:
      //writeBlock(gCycleModal.format(80));
      gCycleModal.reset() // Replacing G80 to reset modal
      forceXYZ();
      gMotionModal.reset() // Forces G00 to be written
    }
  }
}

var currentCoolantMode = COOLANT_OFF;

function setCoolant(coolant) {
  if (coolant == currentCoolantMode) {
    return; // coolant is already active
  }

  var m = undefined;
  if (coolant == COOLANT_OFF) {
    writeBlock(mFormat.format((currentCoolantMode == COOLANT_THROUGH_TOOL) ? 89 : 9));
    currentCoolantMode = COOLANT_OFF;
    return;
  }


  switch (coolant) {
  case COOLANT_FLOOD:
    m = 8;
    break;
  case COOLANT_THROUGH_TOOL:
    m = 88;
    break;
  default:
    onUnsupportedCoolant(coolant);
    m = 9;
  }
  
  if (m) {
    writeBlock(mFormat.format(m));
    currentCoolantMode = coolant;
  }
}

function onCommand(command) {
  switch (command) {
  case COMMAND_COOLANT_OFF:
    setCoolant(COOLANT_OFF);
    return;
  case COMMAND_COOLANT_ON:
    setCoolant(COOLANT_FLOOD);
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_START_CHIP_TRANSPORT:
    return;
  case COMMAND_STOP_CHIP_TRANSPORT:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  case COMMAND_ACTIVATE_SPEED_FEED_SYNCHRONIZATION:
    return;
  case COMMAND_DEACTIVATE_SPEED_FEED_SYNCHRONIZATION:
    return;

  case COMMAND_STOP:
    writeBlock(mFormat.format(0));
    forceSpindleSpeed = true;
    return;
  case COMMAND_OPTIONAL_STOP:
    //writeBlock(mFormat.format(1));
    writeBlock(mFormat.format(0));
    break;
  case COMMAND_END:
    writeBlock(mFormat.format(2));
    break;
  case COMMAND_SPINDLE_CLOCKWISE:
    switch (currentSection.spindle) {
    case SPINDLE_PRIMARY:
      writeBlock(mFormat.format(3));
      break;
    case SPINDLE_SECONDARY:
      writeBlock(mFormat.format(143));
      break;
    }
    break;
  case COMMAND_SPINDLE_COUNTERCLOCKWISE:
    switch (currentSection.spindle) {
    case SPINDLE_PRIMARY:
      writeBlock(mFormat.format(4));
      break;
    case SPINDLE_SECONDARY:
      writeBlock(mFormat.format(144));
      break;
    }
    break;
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_STOP_SPINDLE:
    switch (currentSection.spindle) {
    case SPINDLE_PRIMARY:
      writeBlock(mFormat.format(5));
      break;
    case SPINDLE_SECONDARY:
      writeBlock(mFormat.format(145));
      break;
    }
    break;
  case COMMAND_ORIENTATE_SPINDLE:
    if (getSpindle() == 0) {
      writeBlock(mFormat.format(19)); // use P or R to set angle (optional)
    } else {
      writeBlock(mFormat.format(119));
    }
    break;
  //case COMMAND_CLAMP: // TAG: add support for clamping
  //case COMMAND_UNCLAMP: // TAG: add support for clamping
  default:
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  forceAny();

  if (gotPartCatcher &&
      (currentSection.partCatcher ||
       (typeof currentSection.partCatcher == "undefined") &&
       hasParameter("operation-strategy") &&
       (getParameter("operation-strategy") == "turningPart"))) {
        writeBlock(mFormat.format(23));//hmr
         
    // deactivate part catcher here
  }
}

function onClose() {
if (deBugPost == 1) {
  writeComment("(Entering onClose)");
} 
  //writeln("");

  optionalSection = false;

  onCommand(COMMAND_COOLANT_OFF);

  // we might want to retract in Z before X
  // writeBlock(gFormat.format(28), "U" + xFormat.format(0)); // retract

  forceXYZ();
  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
	  if (deBugPost == 1) {
        writeWords("(Entering onClose and machine has not HomePosition");
      } 
    writeBlock(gFormat.format(28), "U" + xFormat.format(0), conditional(yOutput.isEnabled(), "V" + yFormat.format(0)), "W" + zFormat.format(0)); // return to home
  } else {
    var homeX;
    if (machineConfiguration.hasHomePositionX()) {
      homeX = xOutput.format(machineConfiguration.getHomePositionX());
    }
    var homeY;
    if (yOutput.isEnabled() && machineConfiguration.hasHomePositionY()) {
      homeY = yOutput.format(machineConfiguration.getHomePositionY());
    }
    if (properties.type == "A") {
      writeBlock(gFormat.format(53), mFormat.format(5), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane()));
    } else {
      if (deBugPost == 1) {
        writeComment("(Entering onClose and machine has Home of X or Y(Z)");
      } 
//      writeBlock(gAbsIncModal.format(90), gFormat.format(53), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane()));
      writeBlock("T" + toolFormat.format(0) + toolFormat.format(0)); //This will cancel any tooloffsets in preparation for move to home
      writeBlock(gFormat.format(53),gFormat.format(56), gMotionModal.format(0), homeX, homeY, zOutput.format(machineConfiguration.getRetractPlane())); // Retract to home position
    }
  }

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  if (properties.UnclampChuck) {
    writeBlock(mFormat.format(5));//stop spindle
    writeBlock(gFormat.format(04)+" D455"); // pause to allow spindle to deaccellerate before unclamping d4 and however many 1/10s needed hmr
    writeBlock(mFormat.format(25)); //unclamp chuck
  }
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
  writeln("%");
}
