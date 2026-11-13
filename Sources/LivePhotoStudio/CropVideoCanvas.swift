import SwiftUI

/// Same oriented source and top-left crop coordinates as file export. Editing
/// shows the entire source; completion fits only the selected picture.
struct CropVideoCanvas:View {
 @Bindable var model:Model
 @State private var watermarkDragOrigin:CGPoint?
 @State private var hoveringPreview=false
 var body:some View {
 GeometryReader { geometry in
 let source=model.orientedDisplaySize
 let full=CGRect(origin:.zero,size:source)
 let crop=model.displayCropRect
 let editing=model.cropEditing && model.cropPreset != .off
 let visible=editing ? full : crop
 let scale=min(geometry.size.width/visible.width,geometry.size.height/visible.height)
 ZStack(alignment:.topLeading) {
 NativePlayer(player:model.player)
 .frame(width:source.width*scale,height:source.height*scale)
 .offset(x:-visible.minX*scale,y:-visible.minY*scale)
 if !editing {
  Color.clear
   .contentShape(Rectangle())
   .onHover { hoveringPreview=$0 }
   .onTapGesture { model.togglePreview() }
   .overlay(alignment:.bottom) {
    if hoveringPreview {
     Image(systemName:model.previewing ? "pause.fill" : "play.fill")
      .font(.system(size:14,weight:.semibold))
      .foregroundStyle(.white)
      .frame(width:34,height:34)
      .background(.black.opacity(0.45),in:Circle())
      .padding(12)
      .allowsHitTesting(false)
    }
   }
 }
 if let mark=model.activeWatermark {
 let size=CGSize(width:crop.width*scale,height:crop.height*scale)
 if let (stamp,rect)=mark.stamp(in:size) {
 let draggable=mark.position == 5 && !model.busy && !editing
 Image(decorative:stamp,scale:1).resizable()
 .frame(width:rect.width,height:rect.height).opacity(mark.opacity)
 .contentShape(Rectangle())
 .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("watermarkCanvas"))
 .onChanged { value in
 guard draggable else { return }
 if watermarkDragOrigin == nil { watermarkDragOrigin=CGPoint(x:Watermark.freeCoordinate(mark.freeX),y:Watermark.freeCoordinate(mark.freeY)) }
 guard let origin=watermarkDragOrigin else { return }
 var initial=mark;initial.freeX=origin.x;initial.freeY=origin.y
 let next=initial.freePosition(translatedBy:value.translation,canvasSize:size,stampSize:rect.size)
 model.watermark.freeX=next.x;model.watermark.freeY=next.y
 }
 .onEnded { _ in
 if watermarkDragOrigin != nil { model.watermarkChanged();model.rememberWatermark() }
 watermarkDragOrigin=nil
 })
 .position(x:(crop.minX-visible.minX)*scale+rect.midX,y:(crop.minY-visible.minY)*scale+size.height-rect.midY)
 .allowsHitTesting(draggable)
 }
 }
 if editing {
 CropOverlay(region:Binding(get:{model.cropRegion},set:{if !model.busy {model.cropRegion=$0}}),sourceSize:source,aspect:model.cropPreset.aspect(in:source))
 .frame(width:source.width*scale,height:source.height*scale)
 .disabled(model.busy).allowsHitTesting(!model.busy)
 }
 }
 .coordinateSpace(name:"watermarkCanvas")
 .frame(width:visible.width*scale,height:visible.height*scale,alignment:.topLeading)
 .clipped()
 .position(x:geometry.size.width/2,y:geometry.size.height/2)
 }
 .onChange(of:model.watermark.position) { _,_ in watermarkDragOrigin=nil }
 .onChange(of:model.cropEditing) { _,_ in watermarkDragOrigin=nil }
 }
}
