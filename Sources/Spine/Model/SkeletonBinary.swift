import CoreGraphics
import Foundation

class SkeletonBinary {

    struct BinaryInput {
        let data: Data
        var index: Int = 0
        var strings: [String] = []

        init(data: Data) {
            self.data = data
        }

        mutating func readByte() -> Int8 {
            let value = data[index]
            index += 1
            return Int8(bitPattern: value)
        }

        mutating func readUnsignedByte() -> UInt8 {
            let value = data[index]
            index += 1
            return value
        }

        mutating func readShort() -> Int16 {
            let b1 = UInt16(readUnsignedByte())
            let b2 = UInt16(readUnsignedByte())
            return Int16(bitPattern: (b1 << 8) | b2)
        }

        mutating func readInt32() -> Int32 {
            let b1 = UInt32(readUnsignedByte())
            let b2 = UInt32(readUnsignedByte())
            let b3 = UInt32(readUnsignedByte())
            let b4 = UInt32(readUnsignedByte())
            return Int32(bitPattern: (b1 << 24) | (b2 << 16) | (b3 << 8) | b4)
        }

        mutating func readInt(_ optimizePositive: Bool) -> Int {
            var b = readUnsignedByte()
            var result = Int(b & 0x7F)
            if (b & 0x80) != 0 {
                b = readUnsignedByte()
                result |= Int(b & 0x7F) << 7
                if (b & 0x80) != 0 {
                    b = readUnsignedByte()
                    result |= Int(b & 0x7F) << 14
                    if (b & 0x80) != 0 {
                        b = readUnsignedByte()
                        result |= Int(b & 0x7F) << 21
                        if (b & 0x80) != 0 {
                            b = readUnsignedByte()
                            result |= Int(b & 0x7F) << 28
                        }
                    }
                }
            }
            return optimizePositive ? result : Int((UInt(result) >> 1)) ^ -(result & 1)
        }

        mutating func readString() -> String? {
            let length = readInt(true)
            switch length {
            case 0: return nil
            case 1: return ""
            default:
                let actualLength = length - 1
                let subdata = data.subdata(in: index..<index+actualLength)
                index += actualLength
                return String(data: subdata, encoding: .utf8)
            }
        }

        mutating func readStringRef() -> String? {
            let index = readInt(true)
            return index == 0 ? nil : strings[index - 1]
        }

        mutating func readFloat() -> Float {
            let val = readInt32()
            return Float(bitPattern: UInt32(bitPattern: val))
        }

        mutating func readBoolean() -> Bool {
            return readByte() != 0
        }

        mutating func readColor() -> ColorModel {
            let val = readInt32()
            let r = UInt8((UInt32(bitPattern: val) >> 24) & 0xFF)
            let g = UInt8((UInt32(bitPattern: val) >> 16) & 0xFF)
            let b = UInt8((UInt32(bitPattern: val) >> 8) & 0xFF)
            let a = UInt8(UInt32(bitPattern: val) & 0xFF)
            return ColorModel(value: String(format: "%02X%02X%02X%02X", r, g, b, a))
        }

        mutating func readDarkColor() -> ColorModel? {
            let val = readInt32()
            if val == -1 { return nil }
            let r = UInt8((UInt32(bitPattern: val) >> 16) & 0xFF)
            let g = UInt8((UInt32(bitPattern: val) >> 8) & 0xFF)
            let b = UInt8(UInt32(bitPattern: val) & 0xFF)
            return ColorModel(value: String(format: "%02X%02X%02X", r, g, b))
        }

        mutating func readFloatArray() -> [Float] {
            let n = readInt(true)
            var array = [Float]()
            array.reserveCapacity(n)
            for _ in 0..<n {
                array.append(readFloat())
            }
            return array
        }

        mutating func readShortArray() -> [Int16] {
            let n = readInt(true)
            var array = [Int16]()
            array.reserveCapacity(n)
            for _ in 0..<n {
                array.append(readShort())
            }
            return array
        }

        mutating func readIntArray() -> [Int] {
            let n = readInt(true)
            var array = [Int]()
            array.reserveCapacity(n)
            for _ in 0..<n {
                array.append(readInt(true))
            }
            return array
        }
    }
}

extension SkeletonBinary {

    // Constants mapping for SkeletonBinary
    static let BONE_ROTATE: Int8 = 0
    static let BONE_TRANSLATE: Int8 = 1
    static let BONE_SCALE: Int8 = 2
    static let BONE_SHEAR: Int8 = 3

    static let SLOT_ATTACHMENT: Int8 = 0
    static let SLOT_RGBA: Int8 = 1
    static let SLOT_RGB: Int8 = 2
    static let SLOT_RGBA2: Int8 = 3
    static let SLOT_RGB2: Int8 = 4
    static let SLOT_ALPHA: Int8 = 5

    static let PATH_POSITION: Int8 = 0
    static let PATH_SPACING: Int8 = 1
    static let PATH_MIX: Int8 = 2

    static let CURVE_LINEAR: Int8 = 0
    static let CURVE_STEPPED: Int8 = 1
    static let CURVE_BEZIER: Int8 = 2

    static let ATTACHMENT_REGION: Int8 = 0
    static let ATTACHMENT_BOUNDING_BOX: Int8 = 1
    static let ATTACHMENT_MESH: Int8 = 2
    static let ATTACHMENT_LINKED_MESH: Int8 = 3
    static let ATTACHMENT_PATH: Int8 = 4
    static let ATTACHMENT_POINT: Int8 = 5
    static let ATTACHMENT_CLIPPING: Int8 = 6

    // read curve
    func readCurve(input: inout BinaryInput) -> CurveModel? {
        let curveType = input.readByte()
        switch curveType {
        case SkeletonBinary.CURVE_LINEAR:
            return CurveModel.linear
        case SkeletonBinary.CURVE_STEPPED:
            return CurveModel.stepped
        case SkeletonBinary.CURVE_BEZIER:
            let c1 = input.readFloat()
            let c2 = input.readFloat()
            let c3 = input.readFloat()
            let c4 = input.readFloat()
            return CurveModel.bezier(BezierCurveModel(p0: c1, p1: c2, p2: c3, p3: c4))
        default:
            return nil
        }
    }
}

extension SkeletonBinary {

    func readAttachment(input: inout BinaryInput, name attachmentName: String, nonessential: Bool) -> AttachmentModel? {
        let name = input.readStringRef() ?? attachmentName
        let type = input.readByte()

        switch type {
        case SkeletonBinary.ATTACHMENT_REGION:
            let path = input.readStringRef()
            let rotation = input.readFloat()
            let x = input.readFloat()
            let y = input.readFloat()
            let scaleX = input.readFloat()
            let scaleY = input.readFloat()
            let width = input.readFloat()
            let height = input.readFloat()
            let color = input.readColor()

            // Sequence for region attachment
            let hasSequence = input.readBoolean()
            if hasSequence {
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
            }

            return RegionAttachmentModel(
                name: name,
                fileName: nil,
                path: path,
                position: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                scale: CGVector(dx: CGFloat(scaleX), dy: CGFloat(scaleY)),
                rotation: CGFloat(rotation),
                size: CGSize(width: CGFloat(width), height: CGFloat(height)),
                color: color
            )

        case SkeletonBinary.ATTACHMENT_BOUNDING_BOX:
            let vertexCount = input.readInt(true)
            let vertices = readVertices(input: &input, vertexCount: vertexCount)
            var color = ColorModel(value: "60F000FF")
            if nonessential {
                color = input.readColor()
            }
            return BoundingBoxAttachmentModel(
                name: name,
                vertexCount: UInt(vertexCount),
                vertices: vertices,
                color: color
            )

        case SkeletonBinary.ATTACHMENT_MESH:
            let path = input.readStringRef()
            let color = input.readColor()
            let vertexCount = input.readInt(true)
            let uvs = input.readFloatArray()
            let triangles = input.readShortArray().map { UInt($0) }
            let vertices = readVertices(input: &input, vertexCount: vertexCount)
            let hull = input.readInt(true)
            var edges: [UInt]? = nil
            var width: Float = 0
            var height: Float = 0
            if nonessential {
                edges = input.readShortArray().map { UInt($0) }
                width = input.readFloat()
                height = input.readFloat()
            }

            let hasSequence = input.readBoolean()
            if hasSequence {
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
            }

            return MeshAttachmentModel(
                name: name,
                fileName: nil,
                path: path,
                uvs: uvs.map { CGFloat($0) },
                triangles: triangles,
                vertices: vertices,
                hull: UInt(hull),
                edges: edges,
                color: color,
                width: nonessential ? CGFloat(width) : nil,
                height: nonessential ? CGFloat(height) : nil
            )

        case SkeletonBinary.ATTACHMENT_LINKED_MESH:
            let path = input.readStringRef()
            let color = input.readColor()
            let skin = input.readStringRef()
            let parent = input.readStringRef()
            let deform = input.readBoolean()
            var width: Float = 0
            var height: Float = 0

            let hasSequence = input.readBoolean()
            if hasSequence {
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
                _ = input.readInt(true)
            }

            if nonessential {
                width = input.readFloat()
                height = input.readFloat()
            }

            return LinkedMeshAttachmentModel(
                name: name,
                fileName: nil,
                path: path,
                skin: skin,
                parent: parent ?? "",
                deform: deform,
                color: color,
                width: nonessential ? CGFloat(width) : nil,
                height: nonessential ? CGFloat(height) : nil
            )

        case SkeletonBinary.ATTACHMENT_PATH:
            let closed = input.readBoolean()
            let constantSpeed = input.readBoolean()
            let vertexCount = input.readInt(true)
            let vertices = readVertices(input: &input, vertexCount: vertexCount)
            var lengths = [CGFloat]()
            let lengthsCount = vertexCount / 3
            for _ in 0..<lengthsCount {
                lengths.append(CGFloat(input.readFloat()))
            }
            var color = ColorModel(value: "FF7F00FF")
            if nonessential {
                color = input.readColor()
            }

            return PathAttachmentModel(
                name: name,
                closed: closed,
                constantSpeed: constantSpeed,
                vertexCount: UInt(vertexCount),
                vertices: vertices,
                lengths: lengths,
                color: color
            )

        case SkeletonBinary.ATTACHMENT_POINT:
            let rotation = input.readFloat()
            let x = input.readFloat()
            let y = input.readFloat()
            var color = ColorModel(value: "F1F100FF")
            if nonessential {
                color = input.readColor()
            }
            return PointAttachmentModel(
                name: name,
                position: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                rotation: CGFloat(rotation),
                color: color
            )

        case SkeletonBinary.ATTACHMENT_CLIPPING:
            let endSlot = input.readInt(true)
            let vertexCount = input.readInt(true)
            let vertices = readVertices(input: &input, vertexCount: vertexCount)
            var color = ColorModel(value: "CE3A3AFF")
            if nonessential {
                color = input.readColor()
            }

            return ClippingAttachmentModel(
                name: name,
                end: endSlot.description,
                vertexCount: UInt(vertexCount),
                vertices: vertices,
                color: color
            )

        default:
            return nil
        }
    }

    func readVertices(input: inout BinaryInput, vertexCount: Int) -> [CGFloat] {
        var vertices = [CGFloat]()
        let isWeighted = input.readBoolean()

        if isWeighted {
            for _ in 0..<vertexCount {
                let boneCount = input.readInt(true)
                vertices.append(CGFloat(boneCount))
                for _ in 0..<boneCount {
                    vertices.append(CGFloat(input.readInt(true))) // bone index
                    vertices.append(CGFloat(input.readFloat()))   // bind x
                    vertices.append(CGFloat(input.readFloat()))   // bind y
                    vertices.append(CGFloat(input.readFloat()))   // weight
                }
            }
        } else {
            let n = vertexCount * 2
            for _ in 0..<n {
                vertices.append(CGFloat(input.readFloat()))
            }
        }

        return vertices
    }
}

extension SkeletonBinary {

    func readSkin(input: inout BinaryInput, skeletonData: SpineModel, defaultSkin: Bool, nonessential: Bool) -> SkinModel? {
        let name: String
        var slotCount = 0

        if defaultSkin {
            slotCount = input.readInt(true)
            if slotCount == 0 { return nil }
            name = "default"
        } else {
            name = input.readStringRef() ?? ""

            let bonesCount = input.readInt(true)
            for _ in 0..<bonesCount { _ = input.readInt(true) }

            let ikCount = input.readInt(true)
            for _ in 0..<ikCount { _ = input.readInt(true) }

            let transformCount = input.readInt(true)
            for _ in 0..<transformCount { _ = input.readInt(true) }

            let pathCount = input.readInt(true)
            for _ in 0..<pathCount { _ = input.readInt(true) }

            slotCount = input.readInt(true)
        }

        var skinSlots = [SkinModel.Slot]()
        for _ in 0..<slotCount {
            let slotIndex = input.readInt(true)
            let slotName = skeletonData.slots[slotIndex].name

            var attachments = [AttachmentModel]()
            let attachmentCount = input.readInt(true)
            for _ in 0..<attachmentCount {
                let attachmentName = input.readStringRef() ?? ""
                if let attachment = readAttachment(input: &input, name: attachmentName, nonessential: nonessential) {
                    if let clipping = attachment as? ClippingAttachmentModel, let idx = Int(clipping.end), idx < skeletonData.slots.count {
                        let actualEndName = skeletonData.slots[idx].name
                        let updatedClipping = ClippingAttachmentModel(
                            name: clipping.name,
                            end: actualEndName,
                            vertexCount: clipping.vertexCount,
                            vertices: clipping.vertices,
                            color: clipping.color
                        )
                        attachments.append(updatedClipping)
                    } else {
                        attachments.append(attachment)
                    }
                }
            }
            skinSlots.append(SkinModel.Slot(name: slotName, attachments: attachments))
        }

        return SkinModel(name: name, slots: skinSlots)
    }
}

extension SkeletonBinary {

    func readAnimation(input: inout BinaryInput, name: String, skeletonData: SpineModel) -> AnimationModel {
        var groups = [AnimationModel.Group]()

        let timelinesCount = input.readInt(true)
        _ = timelinesCount

        // Slot timelines
        var slotAnimations = [SlotAnimationModel]()
        let slotCount = input.readInt(true)
        for _ in 0..<slotCount {
            let slotIndex = input.readInt(true)
            guard slotIndex < skeletonData.slots.count else { continue }
            let slotName = skeletonData.slots[slotIndex].name

            var attachments = [SlotKeyframeAttachmentModel]()
            var colors = [SlotKeyframeColorModel]()

            let timelineCount = input.readInt(true)
            for _ in 0..<timelineCount {
                let timelineType = input.readByte()
                let frameCount = input.readInt(true)

                switch timelineType {
                case SkeletonBinary.SLOT_ATTACHMENT:
                    for _ in 0..<frameCount {
                        let time = input.readFloat()
                        let attachmentName = input.readStringRef()
                        attachments.append(SlotKeyframeAttachmentModel(time: CGFloat(time), name: attachmentName))
                    }

                case SkeletonBinary.SLOT_RGBA, SkeletonBinary.SLOT_RGB:
                    let _ = timelineType == SkeletonBinary.SLOT_RGBA ? input.readInt(true) : input.readInt(true)
                    let time = input.readFloat()
                    let colorModel = input.readColor()
                    colors.append(SlotKeyframeColorModel(time: CGFloat(time), color: colorModel, curve: nil))

                    var lastTime = time
                    var lastColor = colorModel

                    for _ in 1..<frameCount {
                        let time2 = input.readFloat()
                        let colorModel2 = input.readColor()
                        let curve = readCurve(input: &input)

                        colors[colors.count - 1] = SlotKeyframeColorModel(time: CGFloat(lastTime), color: lastColor, curve: curve)
                        colors.append(SlotKeyframeColorModel(time: CGFloat(time2), color: colorModel2, curve: nil))

                        lastTime = time2
                        lastColor = colorModel2
                    }

                case SkeletonBinary.SLOT_RGBA2, SkeletonBinary.SLOT_RGB2:
                    let _ = input.readInt(true)
                    _ = input.readFloat()
                    _ = input.readColor()
                    _ = input.readColor()
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        _ = input.readColor()
                        _ = input.readColor()
                        _ = readCurve(input: &input)
                    }

                case SkeletonBinary.SLOT_ALPHA:
                    let _ = input.readInt(true)
                    _ = input.readFloat()
                    _ = input.readFloat()
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        _ = input.readFloat()
                        _ = readCurve(input: &input)
                    }
                default:
                    break
                }
            }

            if !attachments.isEmpty || !colors.isEmpty {
                slotAnimations.append(SlotAnimationModel(
                    slot: slotName,
                    attachment: attachments.isEmpty ? nil : attachments,
                    color: colors.isEmpty ? nil : colors,
                    twoColor: nil
                ))
            }
        }
        if !slotAnimations.isEmpty {
            groups.append(.slots(slotAnimations))
        }

        // Bone timelines
        var boneAnimations = [BoneAnimationModel]()
        let boneCount = input.readInt(true)
        for _ in 0..<boneCount {
            let boneIndex = input.readInt(true)
            guard boneIndex < skeletonData.bones.count else { continue }
            let boneName = skeletonData.bones[boneIndex].name

            var translates = [BoneKeyframeTranslateModel]()
            var rotates = [BoneKeyframeRotateModel]()
            var scales = [BoneKeyframeScaleModel]()
            var shears = [BoneKeyframeShearModel]()

            let timelineCount = input.readInt(true)
            for _ in 0..<timelineCount {
                let timelineType = input.readByte()
                let frameCount = input.readInt(true)

                switch timelineType {
                case SkeletonBinary.BONE_ROTATE:
                    let _ = input.readInt(true)
                    let time = input.readFloat()
                    let angle = input.readFloat()
                    rotates.append(BoneKeyframeRotateModel(time: CGFloat(time), angle: CGFloat(angle), curve: nil))

                    var lastTime = time
                    var lastAngle = angle

                    for _ in 1..<frameCount {
                        let time2 = input.readFloat()
                        let angle2 = input.readFloat()
                        let curve = readCurve(input: &input)
                        rotates[rotates.count - 1] = BoneKeyframeRotateModel(time: CGFloat(lastTime), angle: CGFloat(lastAngle), curve: curve)
                        rotates.append(BoneKeyframeRotateModel(time: CGFloat(time2), angle: CGFloat(angle2), curve: nil))
                        lastTime = time2
                        lastAngle = angle2
                    }

                case SkeletonBinary.BONE_TRANSLATE, SkeletonBinary.BONE_SCALE, SkeletonBinary.BONE_SHEAR:
                    let _ = input.readInt(true)
                    let time = input.readFloat()
                    let x = input.readFloat()
                    let y = input.readFloat()

                    var lastTime = time
                    var lastX = x
                    var lastY = y

                    if timelineType == SkeletonBinary.BONE_TRANSLATE {
                        translates.append(BoneKeyframeTranslateModel(time: CGFloat(time), position: CGPoint(x: CGFloat(x), y: CGFloat(y)), curve: nil))
                    } else if timelineType == SkeletonBinary.BONE_SCALE {
                        scales.append(BoneKeyframeScaleModel(time: CGFloat(time), scale: CGVector(dx: CGFloat(x), dy: CGFloat(y)), curve: nil))
                    } else {
                        shears.append(BoneKeyframeShearModel(time: CGFloat(time), shear: CGVector(dx: CGFloat(x), dy: CGFloat(y)), curve: nil))
                    }

                    for _ in 1..<frameCount {
                        let time2 = input.readFloat()
                        let x2 = input.readFloat()
                        let y2 = input.readFloat()
                        let curve = readCurve(input: &input)

                        if timelineType == SkeletonBinary.BONE_TRANSLATE {
                            translates[translates.count - 1] = BoneKeyframeTranslateModel(time: CGFloat(lastTime), position: CGPoint(x: CGFloat(lastX), y: CGFloat(lastY)), curve: curve)
                            translates.append(BoneKeyframeTranslateModel(time: CGFloat(time2), position: CGPoint(x: CGFloat(x2), y: CGFloat(y2)), curve: nil))
                        } else if timelineType == SkeletonBinary.BONE_SCALE {
                            scales[scales.count - 1] = BoneKeyframeScaleModel(time: CGFloat(lastTime), scale: CGVector(dx: CGFloat(lastX), dy: CGFloat(lastY)), curve: curve)
                            scales.append(BoneKeyframeScaleModel(time: CGFloat(time2), scale: CGVector(dx: CGFloat(x2), dy: CGFloat(y2)), curve: nil))
                        } else {
                            shears[shears.count - 1] = BoneKeyframeShearModel(time: CGFloat(lastTime), shear: CGVector(dx: CGFloat(lastX), dy: CGFloat(lastY)), curve: curve)
                            shears.append(BoneKeyframeShearModel(time: CGFloat(time2), shear: CGVector(dx: CGFloat(x2), dy: CGFloat(y2)), curve: nil))
                        }

                        lastTime = time2
                        lastX = x2
                        lastY = y2
                    }

                default:
                    let _ = input.readInt(true)
                    _ = input.readFloat()
                    _ = input.readFloat()
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        _ = input.readFloat()
                        _ = readCurve(input: &input)
                    }
                    break
                }
            }

            if !translates.isEmpty || !rotates.isEmpty || !scales.isEmpty || !shears.isEmpty {
                boneAnimations.append(BoneAnimationModel(
                    bone: boneName,
                    translate: translates.isEmpty ? nil : translates,
                    rotate: rotates.isEmpty ? nil : rotates,
                    scale: scales.isEmpty ? nil : scales,
                    shear: shears.isEmpty ? nil : shears
                ))
            }
        }

        if !boneAnimations.isEmpty {
            groups.append(.bones(boneAnimations))
        }

        // IK Constraints timelines
        let ikCount = input.readInt(true)
        for _ in 0..<ikCount {
            _ = input.readInt(true)
            let frameCount = input.readInt(true)
            _ = input.readInt(true)
            _ = input.readFloat()
            _ = input.readFloat()
            _ = input.readFloat()
            _ = input.readByte()
            _ = input.readBoolean()
            _ = input.readBoolean()
            for _ in 1..<frameCount {
                _ = input.readFloat()
                _ = input.readFloat()
                _ = input.readFloat()
                _ = input.readByte()
                _ = input.readBoolean()
                _ = input.readBoolean()
                _ = readCurve(input: &input)
            }
        }

        // Transform Constraints timelines
        let transformCount = input.readInt(true)
        for _ in 0..<transformCount {
            _ = input.readInt(true)
            let frameCount = input.readInt(true)
            _ = input.readInt(true)
            _ = input.readFloat()
            _ = input.readFloat()
            _ = input.readFloat()
            _ = input.readFloat()
            _ = input.readFloat()
            for _ in 1..<frameCount {
                _ = input.readFloat()
                _ = input.readFloat()
                _ = input.readFloat()
                _ = input.readFloat()
                _ = input.readFloat()
                _ = readCurve(input: &input)
            }
        }

        // Path Constraints timelines
        let pathCount = input.readInt(true)
        for _ in 0..<pathCount {
            _ = input.readInt(true)
            let timelineCount = input.readInt(true)
            for _ in 0..<timelineCount {
                let timelineType = input.readByte()
                let frameCount = input.readInt(true)
                _ = input.readInt(true)

                switch timelineType {
                case SkeletonBinary.PATH_POSITION, SkeletonBinary.PATH_SPACING:
                    _ = input.readFloat()
                    _ = input.readFloat()
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        _ = input.readFloat()
                        _ = readCurve(input: &input)
                    }
                case SkeletonBinary.PATH_MIX:
                    _ = input.readFloat()
                    _ = input.readFloat()
                    _ = input.readFloat()
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        _ = input.readFloat()
                        _ = input.readFloat()
                        _ = readCurve(input: &input)
                    }
                default: break
                }
            }
        }

        // Deform timelines
        let deformCount = input.readInt(true)
        for _ in 0..<deformCount {
            _ = input.readInt(true)
            let slotCount = input.readInt(true)
            for _ in 0..<slotCount {
                _ = input.readInt(true)
                let timelineCount = input.readInt(true)
                for _ in 0..<timelineCount {
                    _ = input.readStringRef()
                    let frameCount = input.readInt(true)
                    _ = input.readInt(true)
                    _ = input.readFloat()
                    let end = input.readInt(true)
                    if end != 0 {
                        let start = input.readInt(true)
                        for _ in start..<end {
                            _ = input.readFloat()
                        }
                    }
                    for _ in 1..<frameCount {
                        _ = input.readFloat()
                        let end2 = input.readInt(true)
                        if end2 != 0 {
                            let start2 = input.readInt(true)
                            for _ in start2..<end2 {
                                _ = input.readFloat()
                            }
                        }
                        _ = readCurve(input: &input)
                    }
                }
            }
        }

        // DrawOrder timelines
        var drawOrderKeyframes = [DrawOrderKeyframeModel]()
        let drawOrderCount = input.readInt(true)
        for _ in 0..<drawOrderCount {
            let time = input.readFloat()
            let offsetCount = input.readInt(true)
            var offsets = [DrawOrderKeyframeModel.Offset]()
            for _ in 0..<offsetCount {
                let slotIndex = input.readInt(true)
                let amount = input.readInt(true)
                if slotIndex < skeletonData.slots.count {
                    offsets.append(DrawOrderKeyframeModel.Offset(slot: skeletonData.slots[slotIndex].name, offset: amount))
                }
            }
            drawOrderKeyframes.append(DrawOrderKeyframeModel(time: CGFloat(time), offsets: offsets.isEmpty ? nil : offsets))
        }
        if !drawOrderKeyframes.isEmpty {
            groups.append(.drawOrder(drawOrderKeyframes))
        }

        // Event timelines
        var eventKeyframes = [EventKeyfarameModel]()
        let eventCount = input.readInt(true)
        for _ in 0..<eventCount {
            let time = input.readFloat()
            let eventIndex = input.readInt(true)
            let eventDataName = eventIndex < skeletonData.events.count ? skeletonData.events[eventIndex].name : ""
            let intValue = input.readInt(false)
            let floatValue = input.readFloat()
            let hasString = input.readBoolean()
            var stringValue: String? = nil
            if hasString { stringValue = input.readString() }
            var volume: Float = 0
            var balance: Float = 0
            let hasAudio = input.readBoolean()
            if hasAudio {
                volume = input.readFloat()
                balance = input.readFloat()
            }
            eventKeyframes.append(EventKeyfarameModel(
                time: CGFloat(time),
                event: eventDataName,
                int: intValue,
                float: CGFloat(floatValue),
                string: stringValue,
                volume: hasAudio ? CGFloat(volume) : nil,
                balance: hasAudio ? CGFloat(balance) : nil
            ))
        }
        if !eventKeyframes.isEmpty {
            groups.append(.events(eventKeyframes))
        }

        return AnimationModel(name: name, groups: groups)
    }
}

extension SkeletonBinary {

    // Additional helpers for skeleton binary reading
    func readSkeletonData(binary: Data) throws -> SpineModel {
        var input = BinaryInput(data: binary)

        let hashStr = input.readString() ?? ""
        let version = input.readString() ?? ""
        let x = input.readFloat()
        let y = input.readFloat()
        let width = input.readFloat()
        let height = input.readFloat()

        let nonessential = input.readBoolean()
        var fps: Float = 30
        var imagesPath: String? = nil
        var audioPath: String? = nil

        if nonessential {
            fps = input.readFloat()
            imagesPath = input.readString()
            audioPath = input.readString()
        }

        let skeletonModel = SkeletonModel(
            hash: hashStr,
            spine: version,
            position: CGPoint(x: CGFloat(x), y: CGFloat(y)),
            size: CGSize(width: CGFloat(width), height: CGFloat(height)),
            fps: CGFloat(fps),
            images: imagesPath,
            audio: audioPath
        )

        // Strings
        let stringCount = input.readInt(true)
        for _ in 0..<stringCount {
            input.strings.append(input.readString() ?? "")
        }

        // Bones
        var bones = [BoneModel]()
        let bonesCount = input.readInt(true)
        for i in 0..<bonesCount {
            let name = input.readString() ?? ""
            let parentIndex = i == 0 ? -1 : input.readInt(true)
            let parent = parentIndex >= 0 ? bones[parentIndex].name : nil
            let rotation = input.readFloat()
            let bx = input.readFloat()
            let by = input.readFloat()
            let scaleX = input.readFloat()
            let scaleY = input.readFloat()
            let shearX = input.readFloat()
            let shearY = input.readFloat()
            let length = input.readFloat()
            let transformModeInt = input.readInt(true)

            let transformMap: [BoneModel.Transform] = [
                .normal, .onlyTranslation, .noRotationOrReflection, .noScale, .noScaleOrReflection
            ]
            let transformMode = transformModeInt < transformMap.count ? transformMap[transformModeInt] : .normal

            let skinRequired = input.readBoolean()

            var colorModel = ColorModel(value: "989898FF")
            if nonessential {
                colorModel = input.readColor()
            }

            let boneModel = BoneModel(
                name: name,
                parent: parent,
                lenght: CGFloat(length),
                transform: transformMode,
                position: CGPoint(x: CGFloat(bx), y: CGFloat(by)),
                rotation: CGFloat(rotation),
                scale: CGVector(dx: CGFloat(scaleX), dy: CGFloat(scaleY)),
                shear: CGVector(dx: CGFloat(shearX), dy: CGFloat(shearY)),
                inheritScale: true,
                inheritRotation: true,
                color: colorModel
            )
            bones.append(boneModel)
        }

        // Slots
        var slots = [SlotModel]()
        let slotsCount = input.readInt(true)
        for _ in 0..<slotsCount {
            let slotName = input.readString() ?? ""
            let boneIndex = input.readInt(true)
            let boneName = bones[boneIndex].name
            let color = input.readColor()
            let darkColor = input.readDarkColor()
            let attachmentName = input.readStringRef()
            let blendInt = input.readInt(true)

            let blendMap: [SlotModel.BlendMode] = [
                .normal, .additive, .multiply, .screen
            ]
            let blendMode = blendInt < blendMap.count ? blendMap[blendInt] : .normal

            let slotModel = SlotModel(
                name: slotName,
                bone: boneName,
                color: color,
                dark: darkColor,
                attachment: attachmentName,
                blend: blendMode
            )
            slots.append(slotModel)
        }

        // IK Constraints
        var ikConstraints = [IKConstraintModel]()
        let ikCount = input.readInt(true)
        for _ in 0..<ikCount {
            let name = input.readString() ?? ""
            let order = input.readInt(true)
            let skinRequired = input.readBoolean()
            var constraintBones = [String]()
            let constraintBonesCount = input.readInt(true)
            for _ in 0..<constraintBonesCount {
                constraintBones.append(bones[input.readInt(true)].name)
            }
            let target = bones[input.readInt(true)].name
            let mix = input.readFloat()
            let softness = input.readFloat()
            let bendDirection = input.readByte()
            let compress = input.readBoolean()
            let stretch = input.readBoolean()
            let uniform = input.readBoolean()

            let ikModel = IKConstraintModel(
                name: name,
                order: order,
                skinRequired: skinRequired,
                bones: constraintBones,
                target: target,
                mix: CGFloat(mix),
                softness: CGFloat(softness),
                bendPositive: bendDirection > 0,
                compress: compress,
                stretch: stretch,
                uniform: uniform
            )
            ikConstraints.append(ikModel)
        }

        // Transform Constraints
        var transformConstraints = [TransformConstraintModel]()
        let transformCount = input.readInt(true)
        for _ in 0..<transformCount {
            let name = input.readString() ?? ""
            let order = input.readInt(true)
            let skinRequired = input.readBoolean()
            var constraintBones = [String]()
            let constraintBonesCount = input.readInt(true)
            for _ in 0..<constraintBonesCount {
                constraintBones.append(bones[input.readInt(true)].name)
            }
            let target = bones[input.readInt(true)].name
            let local = input.readBoolean()
            let relative = input.readBoolean()
            let offsetRotation = input.readFloat()
            let offsetX = input.readFloat()
            let offsetY = input.readFloat()
            let offsetScaleX = input.readFloat()
            let offsetScaleY = input.readFloat()
            let offsetShearY = input.readFloat()
            let mixRotate = input.readFloat()
            let mixX = input.readFloat()
            let mixY = input.readFloat()
            let mixScaleX = input.readFloat()
            let mixScaleY = input.readFloat()
            let mixShearY = input.readFloat()

            let transformModel = TransformConstraintModel(
                name: name,
                order: order,
                skinRequired: skinRequired,
                bones: constraintBones,
                target: target,
                rotation: CGFloat(offsetRotation),
                position: CGPoint(x: CGFloat(offsetX), y: CGFloat(offsetY)),
                scale: CGVector(dx: CGFloat(offsetScaleX), dy: CGFloat(offsetScaleY)),
                shear: CGVector(dx: 0, dy: CGFloat(offsetShearY)),
                mixRotate: CGFloat(mixRotate),
                mixPosition: CGPoint(x: CGFloat(mixX), y: CGFloat(mixY)),
                mixScale: CGVector(dx: CGFloat(mixScaleX), dy: CGFloat(mixScaleY)),
                mixShear: CGVector(dx: 0, dy: CGFloat(mixShearY)),
                local: local,
                relative: relative
            )
            transformConstraints.append(transformModel)
        }

        // Path Constraints
        var pathConstraints = [PathConstraintModel]()
        let pathCount = input.readInt(true)
        for _ in 0..<pathCount {
            let name = input.readString() ?? ""
            let order = input.readInt(true)
            let skinRequired = input.readBoolean()
            var constraintBones = [String]()
            let constraintBonesCount = input.readInt(true)
            for _ in 0..<constraintBonesCount {
                constraintBones.append(bones[input.readInt(true)].name)
            }
            let target = slots[input.readInt(true)].name
            let positionModeInt = input.readInt(true)
            let spacingModeInt = input.readInt(true)
            let rotateModeInt = input.readInt(true)

            let positionModeMap: [PathConstraintModel.PositionMode] = [.fixed, .percent]
            let spacingModeMap: [PathConstraintModel.SpacingMode] = [.length, .fixed, .percent]
            let rotateModeMap: [PathConstraintModel.RotateMode] = [.tangent, .chain, .chainScale]

            let offsetRotation = input.readFloat()
            let position = input.readFloat()
            let spacing = input.readFloat()
            let mixRotate = input.readFloat()
            let mixX = input.readFloat()
            let mixY = input.readFloat()

            let pathModel = PathConstraintModel(
                name: name,
                order: order,
                skinRequired: skinRequired,
                bones: constraintBones,
                target: target,
                positionMode: positionModeInt < positionModeMap.count ? positionModeMap[positionModeInt] : .percent,
                spacingMode: spacingModeInt < spacingModeMap.count ? spacingModeMap[spacingModeInt] : .length,
                rotateMode: rotateModeInt < rotateModeMap.count ? rotateModeMap[rotateModeInt] : .tangent,
                rotation: CGFloat(offsetRotation),
                position: CGFloat(position),
                spacing: CGFloat(spacing),
                mixRotate: CGFloat(mixRotate),
                mixPosition: CGPoint(x: CGFloat(mixX), y: CGFloat(mixY))
            )
            pathConstraints.append(pathModel)
        }

        let defaultSkin = readSkin(input: &input, skeletonData: SpineModel(
            skeleton: skeletonModel,
            bones: bones,
            slots: slots,
            skins: [],
            ik: ikConstraints,
            transform: transformConstraints,
            path: pathConstraints,
            events: [],
            animations: []
        ), defaultSkin: true, nonessential: nonessential)

        var skins = [SkinModel]()
        if let defaultSkin = defaultSkin {
            skins.append(defaultSkin)
        }

        let dummyModelForSkin = SpineModel(
            skeleton: skeletonModel,
            bones: bones,
            slots: slots,
            skins: [],
            ik: ikConstraints,
            transform: transformConstraints,
            path: pathConstraints,
            events: [],
            animations: []
        )

        let skinsCount = input.readInt(true)
        for _ in 0..<skinsCount {
            if let skin = readSkin(input: &input, skeletonData: dummyModelForSkin, defaultSkin: false, nonessential: nonessential) {
                skins.append(skin)
            }
        }

        // Events
        var events = [EventModel]()
        let eventsCount = input.readInt(true)
        for _ in 0..<eventsCount {
            let eventName = input.readStringRef() ?? ""
            let intValue = input.readInt(false)
            let floatValue = input.readFloat()
            let stringValue = input.readString()
            let audioPath = input.readString()
            var volume: Float = 0
            var balance: Float = 0
            if audioPath != nil {
                volume = input.readFloat()
                balance = input.readFloat()
            }
            events.append(EventModel(
                name: eventName,
                int: intValue,
                float: floatValue,
                string: stringValue,
                audio: audioPath,
                volume: audioPath != nil ? volume : 1,
                balance: audioPath != nil ? balance : 0
            ))
        }

        let skeletonDataWithEvents = SpineModel(
            skeleton: skeletonModel,
            bones: bones,
            slots: slots,
            skins: skins,
            ik: ikConstraints,
            transform: transformConstraints,
            path: pathConstraints,
            events: events,
            animations: []
        )

        // Animations
        var animations = [AnimationModel]()
        let animationsCount = input.readInt(true)
        for _ in 0..<animationsCount {
            let animationName = input.readString() ?? ""
            let animation = readAnimation(input: &input, name: animationName, skeletonData: skeletonDataWithEvents)
            animations.append(animation)
        }

        return SpineModel(
            skeleton: skeletonModel,
            bones: skeletonDataWithEvents.bones,
            slots: skeletonDataWithEvents.slots,
            skins: skins,
            ik: skeletonDataWithEvents.ik,
            transform: skeletonDataWithEvents.transform,
            path: skeletonDataWithEvents.path,
            events: events,
            animations: animations
        )
    }
}
