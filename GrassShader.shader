Shader "Custom/GrassShader"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _GrassTipColor("Grass Tip Color", Color) = (1, 1, 1, 1)
        _BladeTexture("Blade Texture", 2D) = "white" {}
        
        _BladeWidthMin("Blade Minimum Width", Range(0, 0.1)) = 0.015
        _BladeWidthMax("Blade Maximum Width", Range(0, 0.1)) = 0.06
        _BladeHeightMin("Blade Minimum Height", Range(0, 5)) = 0.1
        _BladeHeightMax("Blade Maximum Height", Range(0, 5)) = 0.2
        
        _BladeSegments("Blade Segments", Int) = 3
		_BladeBendDistance("Blade Forward Amount", Float) = 0.38
		_BladeBendCurve("Blade Curvature Amount", Range(1, 4)) = 2
    	
    	_BendDelta("Bend Variation", Range(0, 1)) = 0.2
    	
    	_TessellationGrassDistance("Tessellation Grass Distance", Range(0.01, 2)) = 0.1

    	_GrassMap("Grass Visibility Map", 2D) = "white" {}
		_GrassThreshold("Grass Visibility Threshold", Range(-0.1, 1)) = 0.5
		_GrassFalloff("Grass Visibility Fade-In Falloff", Range(0, 0.5)) = 0.05
    	
    	_WindMap("Wind Offset Map", 2D) = "bump" {}
		_WindVelocity("Wind Velocity", Vector) = (1, 0, 0, 0)
		_WindFrequency("Wind Pulse Frequency", Range(0, 1)) = 0.01
    }
    SubShader
    {
    	Tags
		{
			"RenderType" = "Opaque"
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}
		LOD 100
		Cull Off
    	
    	HLSLINCLUDE
    		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

    		#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _SHADOWS_SOFT

    		#define UNITY_PI 3.14159265359f
			#define UNITY_TWO_PI 6.28318530718f
			#define BLADE_SEGMENTS 4

		    CBUFFER_START(UnityPerMaterial)
			    float4 _BaseColor;
			    float4 _GrassTipColor;
			    sampler2D _BladeTexture;

			    float _BladeWidthMin;
			    float _BladeWidthMax;
			    float _BladeHeightMin;
			    float _BladeHeightMax;

    			int _BladeSegments;
			    float _BladeBendDistance;
			    float _BladeBendCurve;

			    float _BendDelta;

			    float _TessellationGrassDistance;

			    sampler2D _GrassMap;
			    float4 _GrassMap_ST;
			    float _GrassThreshold;
			    float _GrassFalloff;

			    sampler2D _WindMap;
    			// Unity provides value for float4 with "_ST" suffix.
    			// The x,y contains texture scale, and z,w contains translation (offset)
			    float4 _WindMap_ST; 
			    float4 _WindVelocity;
			    float _WindFrequency;

			    float4 _ShadowColor;
		    CBUFFER_END

    		// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
			// Extended discussion on this function can be found at the following link:
			// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
			// Returns a number in the 0...1 range.
			float rand(float3 co)
			{
				return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
			}

    		// Construct a rotation matrix that rotates around the provided axis, sourced from:
			// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
			float3x3 angleAxis3x3(float angle, float3 axis)
			{
				float c, s;
				sincos(angle, s, c);

				float t = 1 - c;
				float x = axis.x;
				float y = axis.y;
				float z = axis.z;

				return float3x3
				(
					t * x * x + c, t * x * y - s * z, t * x * z + s * y,
					t * x * y + s * z, t * y * y + c, t * y * z - s * x,
					t * x * z - s * y, t * y * z + s * x, t * z * z + c
				);
			}

    		// Basic Vertex stuff...
			struct VertexInput
		    {
			    float4 vertex : POSITION;
		    	float3 normal : NORMAL;
		    	float4 tangent : TANGENT;
		    	float2 uv : TEXCOORD0;
		    };

    		struct VertexOutput
    		{
    			float4 vertex : SV_POSITION;
    			float3 normal : NORMAL;
    			float4 tangent : TANGENT;
    			float2 uv : TEXCOORD0;
    		};

    		// For Geometric shader and creating grass
    		struct GeometricData
    		{
    			float4 pos : SV_POSITION;
    			float2 uv : TEXCOORD0;
    			float3 worldPos : TEXCOORD1;
    		};

    		// Structs for tessellation
    		struct TessellationFactors
    		{
    			float edge[3] : SV_TessFactor;
    			float inside : SV_InsideTessFactor;
    		};

    		// Simple vertex shader
    		VertexOutput vert(VertexInput vIn)
    		{
    			VertexOutput vOut;
    			vOut.vertex = TransformObjectToHClip(vIn.vertex.xyz);
    			vOut.normal = vIn.normal;
    			vOut.tangent = vIn.tangent;
    			vOut.uv = TRANSFORM_TEX(vIn.uv, _GrassMap);
    			
    			return vOut;
    		}

    		// Tesselation Vertex, just copies everything
    		VertexOutput tessVert(VertexInput vIn)
    		{
    			VertexOutput vOut;
    			vOut.vertex = vIn.vertex;
    			vOut.tangent = vIn.tangent;
    			vOut.normal = vIn.normal;
    			vOut.uv = vIn.uv;

    			return vOut;
    		}

    		// Geometric Shader things
			VertexOutput geomVert(VertexInput vIn)
    		{
    			VertexOutput vOut;
    			vOut.vertex = float4(TransformObjectToWorld(vIn.vertex), 1.0f); // Transforms to world position
    			vOut.normal = TransformObjectToWorldNormal(vIn.normal);
    			vOut.tangent = vIn.tangent;
    			vOut.uv = TRANSFORM_TEX(vIn.uv, _GrassMap);
    			
    			return vOut;
    		}

    		// Tessleation Shader stuff

    		// Tessellation factor for an edge based on viewer position
    		float tesselationEdgeFactor(VertexInput vIn_0, VertexInput vIn_1)
    		{
    			float3 v0 = vIn_0.vertex.xyz;
    			float3 v1 = vIn_1.vertex.xyz;
    			float edgeLength = distance(v0, v1);

				// float3 edgeCenter = (v0 + v1) * 0.5f;
				// float viewDist = distance(edgeCenter, _WorldSpaceCameraPos) / 10.0f;
    			
    			// float result = edgeLength * _ScreenParams.y / (_TessellationGrassDistance * viewDist);

    			float result = edgeLength / _TessellationGrassDistance;

    			return result;
    		}

    		// The patch constant function to create control points on the patch.
    		// Increasing tessellation factors adds new vertices on each edge.
    		TessellationFactors patchConstantFunc(InputPatch<VertexInput, 3> patch)
    		{
    			TessellationFactors fac;

    			fac.edge[0] = tesselationEdgeFactor(patch[1], patch[2]);
    			fac.edge[1] = tesselationEdgeFactor(patch[2], patch[0]);
    			fac.edge[2] = tesselationEdgeFactor(patch[0], patch[1]);
    			fac.inside = (fac.edge[0] + fac.edge[1] + fac.edge[2]) / 3.0f; // New vertex

    			return fac;
    		}

    		// The hull function for the tessellation shader.
    		// Operates on each patch, and outputs new control points for tessellation stages
    		[domain("tri")]
    		[outputcontrolpoints(3)]
    		[outputtopology("triangle_cw")]
    		[partitioning("integer")]
    		[patchconstantfunc("patchConstantFunc")]
    		VertexInput hull(InputPatch<VertexInput, 3> patch, uint id : SV_OutputControlPointID)
    		{
    			return patch[id];
    		}

    		// The graphics pipeline will generate new vertices

    		// The domain function for the tessellation shader
    		// It interpolates the properties of vertices to create new vertices
    		[domain("tri")]
			VertexOutput domain(TessellationFactors factors, OutputPatch<VertexInput, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
    		{
    			VertexInput vIn;
    			// barycentricCoordinates are weighted coordinates of each vertices
    			
    			#define INTERPOLATE(fieldname) vIn.fieldname = \
    				patch[0].fieldname * barycentricCoordinates.x + \
    				patch[1].fieldname * barycentricCoordinates.y + \
    				patch[2].fieldname * barycentricCoordinates.z;

    			INTERPOLATE(vertex)
    			INTERPOLATE(normal)
    			INTERPOLATE(tangent)
    			INTERPOLATE(uv)

    			return tessVert(vIn);
    		}

    		
    		// Transform to clip space for Geometric Shader
			GeometricData transformGeomToClip(float3 pos, float3 offset, float3x3 transformMat, float2 uv)
    		{
    			GeometricData gOut;
    			// gOut.pos = TransformObjectToHClip(pos + mul(transformMat, offset));
				gOut.pos = TransformWorldToHClip(pos + mul(transformMat, offset));
    			
    			gOut.uv = uv;
    			// gOut.worldPos = TransformObjectToWorld(pos + mul(transformMat, offset));
    			// gOut.worldPos = TransformWorldToHClip(pos + mul(transformMat, offset));
    			gOut.worldPos = pos;
    			
    			return gOut;
    		}

    		// This is because at each segment, we add 2 vertices, and there is always 1 vertex at the tip
    		[maxvertexcount(BLADE_SEGMENTS * 2 + 1)] 
    		void geom(point VertexOutput input[1], inout TriangleStream<GeometricData> triangleStream)
    		{

				// Read from the Grass Map texture
    			float grassVisibility = tex2Dlod(_GrassMap, float4(input[0].uv, 0, 0)).r;

    			// Check if the grass needs to spawn or not
    			if (grassVisibility >= _GrassThreshold)
    			{
    			
    				float3 pos = input[0].vertex.xyz;
    				float3 normal = input[0].normal;
    				float4 tangent = input[0].tangent;

    				float3 bitangent = cross(normal, tangent.xyz) * tangent.w;

    				float3x3 tangentToLocal = float3x3
    				(
    					tangent.x, bitangent.x, normal.x,
    					tangent.y, bitangent.y, normal.y,
    					tangent.z, bitangent.z, normal.z
					);

    				// Rotate around y-axis by some random amount
    				float3x3 randRotateMat = angleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1.0f));

    				// Rotate around the bottom of the blade by some random amount
    				float3x3 randBendMat = angleAxis3x3(rand(pos.zzx) * _BendDelta * UNITY_PI * 0.5f, float3(-1.0f, 0, 0));

    				// float3x3 transformMat = float3x3
    				// (
    				// 	1, 0, 0,
    				// 	0, 1, 0,
    				// 	0, 0, 1
    				// );

    				// Sampling from wind texture
    				float2 windUV = pos.xz * _WindMap_ST.xy + _WindMap_ST.zw + normalize(_WindVelocity.xzy) * _WindFrequency * _Time.y;
    				float2 windSample = (tex2Dlod(_WindMap, float4(windUV, 0, 0)).xy * 2 - 1) * length(_WindVelocity);

					// Wind Transforms
    				float3 windAxis = normalize(float3(windSample.x, windSample.y, 0));
    				float3x3 windMat = angleAxis3x3(UNITY_PI * windSample, windAxis);

    				// Transform matrices for base and tip of a blade
    				float3x3 baseTransformMat = mul(tangentToLocal, randRotateMat);
    				float3x3 tipTransformMat = mul(mul(mul(tangentToLocal, windMat), randBendMat), randRotateMat);
    				
					float falloff = smoothstep(_GrassThreshold, _GrassThreshold + _GrassFalloff, grassVisibility);
    				
    				float width = lerp(_BladeWidthMin, _BladeWidthMax, rand(pos.xyz) * falloff);
    				float height = lerp(_BladeHeightMin, _BladeHeightMax, rand(pos.zyx) * falloff);
    				float forward = rand(pos.yyz) * _BladeBendDistance;

    				for (int i = 0; i < _BladeSegments; i++)
    				{
    					float t = i / (float)_BladeSegments;
    					float3 offset = float3(width * (1 - t), pow(t, _BladeBendCurve) * forward, height * t);

    					float3x3 transformMat;
    					if (i == 0)
    					{
    						transformMat = baseTransformMat;
    					}
					    else
					    {
						    transformMat = tipTransformMat;
					    }

    					// Data for a single strip (for each 2 vertices
    					triangleStream.Append(transformGeomToClip(pos, float3(offset.x, offset.y, offset.z), transformMat, float2(0, t)));
    					triangleStream.Append(transformGeomToClip(pos, float3(-offset.x, offset.y, offset.z), transformMat, float2(1, t)));
    					
    				}

    				// Adding for the tip
    				triangleStream.Append(transformGeomToClip(pos, float3(0, forward, height), tipTransformMat, float2(0.5, 1)));

    				// Data for a single strip
    				// triangleStream.Append(transformGeomToClip(pos, float3(-0.1f, 0.0f, 0.0f), baseTransformMat, float2(0.0f, 0.0f)));
    				// triangleStream.Append(transformGeomToClip(pos, float3(0.1f, 0.0f, 0.0f), baseTransformMat, float2(1.0f, 0.0f)));
    				// triangleStream.Append(transformGeomToClip(pos, float3(0.0f, 0.0f, 0.5f), tipTransformMat, float2(0.5f, 1.0f)));

    				triangleStream.RestartStrip();
    			}
    		}
    		
    	ENDHLSL

		Pass
		{
			Name "GrassPass"
			Tags{ "LightMode" = "UniversalForward" }
			
			HLSLPROGRAM
				#pragma require geometry
				#pragma require tessellation tessHW
				
				#pragma vertex geomVert
				#pragma hull hull
				#pragma domain domain
				#pragma	geometry geom
				#pragma fragment frag
				
				float4 frag(GeometricData gIn) : SV_Target
				{
					float4 color = tex2D(_BladeTexture, gIn.uv);
					
					#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
						VertexPositionInputs vertexInput = (VertexPositionInputs)0;
						vertexInput.positionWS = gIn.worldPos;

						float4 shadowCoord = GetShadowCoord(vertexInput);
						half shadowAttenuation = saturate(MainLightRealtimeShadow(shadowCoord) + 0.25f);
						float4 shadowColor = lerp(0.0f, 1.0f, shadowAttenuation);
						color *= shadowColor;
					#endif
					
					return color * lerp(_BaseColor, _GrassTipColor, gIn.uv.y);
				}
				
			ENDHLSL
		}
	}
}
