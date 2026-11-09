import { ThreeCanvas } from "@remotion/three";
import { Center, Text3D } from "@react-three/drei";
import { AbsoluteFill, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { z } from "zod";

export const text3DSchema = z.object({
  text: z.string(),
  color: z.string(),
  background: z.string(),
});

// Extruded 3D title: springs in from depth, then turns slowly. Font is a typeface JSON made by scripts/font-to-typeface.mjs.
export const Text3DTitle: React.FC<z.infer<typeof text3DSchema>> = ({ text, color, background }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 14, stiffness: 120 } });
  const turn = interpolate(frame, [0, 4 * fps], [-0.35, 0.25]);
  // A vertical frame shows ~4.2 units across at z=9; Anton glyphs are ~0.55 of the size wide.
  const size = Math.min(1.6, 3.4 / (Math.max(1, [...text].length) * 0.55));

  return (
    <AbsoluteFill style={{ background }}>
      <ThreeCanvas width={width} height={height} camera={{ position: [0, 0, 9], fov: 45 }}>
        <ambientLight intensity={0.5} />
        <directionalLight position={[4, 6, 8]} intensity={2.4} />
        <pointLight position={[-5, -2, 4]} intensity={40} color="#ec4899" />
        <group scale={interpolate(enter, [0, 1], [0.2, 1])} rotation={[0.12, turn, 0]} position={[0, 0, interpolate(enter, [0, 1], [-6, 0])]}>
          <Center>
            <Text3D font={staticFile("fonts/anton.typeface.json")} size={size} height={size * 0.28} bevelEnabled bevelSize={0.04} bevelThickness={0.06} curveSegments={8}>
              {text}
              <meshStandardMaterial color={color} metalness={0.35} roughness={0.3} />
            </Text3D>
          </Center>
        </group>
      </ThreeCanvas>
    </AbsoluteFill>
  );
};
