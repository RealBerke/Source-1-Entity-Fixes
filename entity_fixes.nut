// Written by Berke.

class EntityFixesFix
{
	hEntity = null;
	fCondition = null;
	fSpawnFunction = null;
	fPostSpawnFunction = null;
	fThinkFunction = null;

	constructor(hInputEntity, fInputCondition, fInputSpawnFunction, fInputPostSpawnFunction = null, fInputThinkFunction = null)
	{
		hEntity = hInputEntity,
		fCondition = fInputCondition,
		fSpawnFunction = fInputSpawnFunction,
		fPostSpawnFunction = fInputPostSpawnFunction,
		fThinkFunction = fInputThinkFunction;
	}

	function Init()
	{
		local hScriptScope = hEntity.GetScriptScope();

		if (!fCondition.call(hScriptScope))
			return false;

		if (fSpawnFunction)
			fSpawnFunction.call(hScriptScope);

		if (fPostSpawnFunction)
			hScriptScope.OnPostSpawn <- fPostSpawnFunction;

		if (!fThinkFunction || hEntity.GetScriptThinkFunc() != "")
			return;

		hScriptScope.OnEntityFixesThink <- fThinkFunction;
		AddThinkToEnt(hEntity, "OnEntityFixesThink");

		return true;
	}
}

aEntityFixesInits <-
[
	EntityFixesFix
	(
		self,
		function()
		{
			if (!self.GetMoveParent())
				return false;

			local strClassname = self.GetClassname();

			return strClassname == "func_movelinear" || strClassname == "momentary_door" || strClassname == "func_water_analog";
		},
		function()
		{
			flEntityFixesMoveDoneDuration <- 0.0;
		},
		function()
		{
			local vOrigin = self.GetLocalOrigin(),
			vDirection = NetProps.GetPropVector(self, "m_vecMoveDir"),
			flDistance = NetProps.GetPropFloat(self, "m_flMoveDistance"),
			vStartPosition = vOrigin - vDirection * flDistance * NetProps.GetPropFloat(self, "m_flStartPosition");
			NetProps.SetPropVector(self, "m_vecPosition1", vStartPosition);
			NetProps.SetPropVector(self, "m_vecPosition2", vStartPosition + vDirection * flDistance);
			NetProps.SetPropVector(self, "m_vecFinalDest", vOrigin);
		},
		function()
		{
			local flPreviousMoveDuration = flEntityFixesMoveDoneDuration;
			flEntityFixesMoveDoneDuration = NetProps.GetPropFloat(self, "m_flMoveDoneTime");

			if (flPreviousMoveDuration == -1 || flEntityFixesMoveDoneDuration != -1)
				return 0;

			local vOrigin = self.GetLocalOrigin(),
			vOriginX = vOrigin.x,
			vOriginY = vOrigin.y,
			vOriginZ = vOrigin.z,
			aChecks =
			[
				{
					strPositionVariable = "m_vecPosition2",
					strOutput = "OnFullyOpen"
				},
				{
					strPositionVariable = "m_vecPosition1",
					strOutput = "OnFullyClosed"
				}
			];

			foreach (tCheck in aChecks)
			{
				local vTargetPosition = NetProps.GetPropVector(self, tCheck.strPositionVariable);

				if (vOriginX != vTargetPosition.x || vOriginY != vTargetPosition.y || vOriginZ != vTargetPosition.z)
					continue;

				local strOutput = tCheck.strOutput;

				if (!EntityOutputs.HasAction(self, strOutput))
					break;

				for (local iOutputIndex = EntityOutputs.GetNumElements(self, strOutput) - 1; iOutputIndex >= 0; iOutputIndex--)
				{
					local tOutputInfo = {};
					EntityOutputs.GetOutputTable(self, strOutput, tOutputInfo, iOutputIndex);
					local strTarget = tOutputInfo.target,
					strInput = tOutputInfo.input,
					strParameter = tOutputInfo.parameter,
					flDelay = tOutputInfo.delay;
					DoEntFire(strTarget, strInput, strParameter, flDelay, self, self);
					local iFireCount = tOutputInfo.times_to_fire;

					if (iFireCount <= 0)
						continue;

					EntityOutputs.RemoveOutput(self, strOutput, strTarget, strInput, strParameter);

					if (iFireCount == 1)
						continue;

					EntityOutputs.AddOutput(self, strOutput, strTarget, strInput, strParameter, flDelay, iFireCount - 1);
				}

				break;
			}

			return 0;
		}
	),
	EntityFixesFix
	(
		self,
		@() self.GetClassname() == "func_rotating",
		null,
		null,
		function()
		{
			if (!NetProps.GetPropFloat(self, "m_flSpeed"))
				return 0;

			local qaAngle = self.GetLocalAngles(),
			flAnglePitch = qaAngle.Pitch(),
			flAngleYaw = qaAngle.Yaw(),
			flAngleRoll = qaAngle.Roll();

			if (flAnglePitch > -180 && flAnglePitch <= 180 && flAngleYaw > -180 && flAngleYaw <= 180 && flAngleRoll > -180 && flAngleRoll <= 180)
				return 0;

			flAnglePitch %= 360;

			if (flAnglePitch <= -180)
				flAnglePitch += 360;

			else if (flAnglePitch > 180)
				flAnglePitch -= 360;

			flAngleYaw %= 360;

			if (flAngleYaw <= -180)
				flAngleYaw += 360;

			else if (flAngleYaw > 180)
				flAngleYaw -= 360;

			flAngleRoll %= 360;

			if (flAngleRoll <= -180)
				flAngleRoll += 360;

			else if (flAngleRoll > 180)
				flAngleRoll -= 360;

			self.SetLocalAngles(QAngle(flAnglePitch, flAngleYaw, flAngleRoll));

			return 0;
		}
	),
	EntityFixesFix
	(
		self,
		@() self.GetClassname() == "point_teleport" && !(NetProps.GetPropInt(self, "m_spawnflags") & 1),
		null,
		null,
		function()
		{
			NetProps.SetPropVector(self, "m_vSaveOrigin", self.GetOrigin());
			local qaAngles = self.GetAbsAngles();
			NetProps.SetPropVector(self, "m_vSaveAngles", Vector(qaAngles.Pitch(), qaAngles.Yaw(), qaAngles.Roll()));

			return 0;
		}
	),
	EntityFixesFix
	(
		self,
		function()
		{
			if (self.GetClassname() != "trigger_push")
				return false;

			local qaAngle = self.GetAbsAngles();

			return qaAngle.Pitch() || qaAngle.Yaw() || qaAngle.Roll();
		},
		function()
		{
			local vPushAngle = NetProps.GetPropVector(self, "m_vecPushDir"),
			qaPushAngle = RotateOrientation(QAngle(vPushAngle.x, vPushAngle.y, vPushAngle.z), self.GetAbsAngles());
			NetProps.SetPropVector(self, "m_vecPushDir", Vector(qaPushAngle.Pitch(), qaPushAngle.Yaw(), qaPushAngle.Roll()));
		}
	)
];

delete EntityFixesFix;

foreach (cEntityFixesFix in aEntityFixesInits)
	if (cEntityFixesFix.Init())
		break;


delete aEntityFixesInits;




