import { ClassValue } from 'clsx';
import * as class_variance_authority_types from 'class-variance-authority/types';
import * as React$1 from 'react';
import React__default, { RefObject, ReactNode } from 'react';
import { VariantProps } from 'class-variance-authority';
import { AlertDialog as AlertDialog$1, Avatar as Avatar$1, Checkbox as Checkbox$1, Collapsible as Collapsible$1, Dialog as Dialog$1, DropdownMenu as DropdownMenu$1, HoverCard as HoverCard$1, Label as Label$1, Popover as Popover$1, Progress as Progress$1, RadioGroup as RadioGroup$1, Select as Select$1, Separator as Separator$1, Slider as Slider$1, Switch as Switch$1, Tabs as Tabs$1, Tooltip as Tooltip$1 } from 'radix-ui';
import { Transition } from 'motion/react';
import { DayPicker, DayButton, Locale } from 'react-day-picker';
import { Command as Command$1 } from 'cmdk';
import { Options, GlobalOptions } from 'canvas-confetti';
import { ToasterProps } from 'sonner';

declare function cn(...inputs: ClassValue[]): string;

declare const alertVariants: (props?: ({
    variant?: "default" | "destructive" | "warning" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function Alert({ className, variant, ...props }: React$1.ComponentProps<"div"> & VariantProps<typeof alertVariants>): React$1.JSX.Element;
declare function AlertTitle({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AlertDescription({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AlertAction({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;

declare const buttonVariants: (props?: ({
    variant?: "default" | "destructive" | "link" | "outline" | "secondary" | "ghost" | null | undefined;
    size?: "default" | "xs" | "sm" | "lg" | "icon" | "icon-xs" | "icon-sm" | "icon-lg" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function Button({ className, variant, size, asChild, ...props }: React$1.ComponentProps<"button"> & VariantProps<typeof buttonVariants> & {
    asChild?: boolean;
}): React$1.JSX.Element;

declare function AlertDialog({ ...props }: React$1.ComponentProps<typeof AlertDialog$1.Root>): React$1.JSX.Element;
declare function AlertDialogTrigger({ ...props }: React$1.ComponentProps<typeof AlertDialog$1.Trigger>): React$1.JSX.Element;
declare function AlertDialogPortal({ ...props }: React$1.ComponentProps<typeof AlertDialog$1.Portal>): React$1.JSX.Element;
declare function AlertDialogOverlay({ className, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Overlay>): React$1.JSX.Element;
declare function AlertDialogContent({ className, size, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Content> & {
    size?: "default" | "sm";
}): React$1.JSX.Element;
declare function AlertDialogHeader({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AlertDialogFooter({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AlertDialogMedia({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AlertDialogTitle({ className, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Title>): React$1.JSX.Element;
declare function AlertDialogDescription({ className, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Description>): React$1.JSX.Element;
declare function AlertDialogAction({ className, variant, size, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Action> & Pick<React$1.ComponentProps<typeof Button>, "variant" | "size">): React$1.JSX.Element;
declare function AlertDialogCancel({ className, variant, size, ...props }: React$1.ComponentProps<typeof AlertDialog$1.Cancel> & Pick<React$1.ComponentProps<typeof Button>, "variant" | "size">): React$1.JSX.Element;

declare function AnimatedBeam({ className, containerRef, fromRef, toRef, curvature, reverse, duration, delay, pathColor, pathWidth, pathOpacity, gradientStartColor, gradientStopColor, repeat, repeatDelay, startXOffset, startYOffset, endXOffset, endYOffset, }: {
    className?: string;
    containerRef: RefObject<HTMLElement | null>;
    fromRef: RefObject<HTMLElement | null>;
    toRef: RefObject<HTMLElement | null>;
    curvature?: number;
    reverse?: boolean;
    pathColor?: string;
    pathWidth?: number;
    pathOpacity?: number;
    gradientStartColor?: string;
    gradientStopColor?: string;
    delay?: number;
    duration?: number;
    repeat?: number;
    repeatDelay?: number;
    startXOffset?: number;
    startYOffset?: number;
    endXOffset?: number;
    endYOffset?: number;
}): React$1.JSX.Element;

declare function Avatar({ className, size, ...props }: React$1.ComponentProps<typeof Avatar$1.Root> & {
    size?: "default" | "sm" | "lg";
}): React$1.JSX.Element;
declare function AvatarImage({ className, ...props }: React$1.ComponentProps<typeof Avatar$1.Image>): React$1.JSX.Element;
declare function AvatarFallback({ className, ...props }: React$1.ComponentProps<typeof Avatar$1.Fallback>): React$1.JSX.Element;
declare function AvatarBadge({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;
declare function AvatarGroup({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function AvatarGroupCount({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;

declare const badgeVariants: (props?: ({
    variant?: "default" | "destructive" | "warning" | "link" | "outline" | "secondary" | "ghost" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function Badge({ className, variant, asChild, ...props }: React$1.ComponentProps<"span"> & VariantProps<typeof badgeVariants> & {
    asChild?: boolean;
}): React$1.JSX.Element;

declare function BentoGrid({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function BentoCard({ name, className, background, Icon, description, href, cta, ...props }: React$1.ComponentProps<"div"> & {
    name: string;
    className: string;
    background: React$1.ReactNode;
    Icon: React$1.ElementType;
    description: string;
    href: string;
    cta: string;
}): React$1.JSX.Element;

declare function BorderBeam({ className, size, delay, duration, colorFrom, colorTo, transition, style, reverse, initialOffset, borderWidth, }: {
    size?: number;
    duration?: number;
    delay?: number;
    colorFrom?: string;
    colorTo?: string;
    transition?: Transition;
    className?: string;
    style?: React$1.CSSProperties;
    reverse?: boolean;
    initialOffset?: number;
    borderWidth?: number;
}): React$1.JSX.Element;

declare function Breadcrumb({ className, ...props }: React$1.ComponentProps<"nav">): React$1.JSX.Element;
declare function BreadcrumbList({ className, ...props }: React$1.ComponentProps<"ol">): React$1.JSX.Element;
declare function BreadcrumbItem({ className, ...props }: React$1.ComponentProps<"li">): React$1.JSX.Element;
declare function BreadcrumbLink({ asChild, className, ...props }: React$1.ComponentProps<"a"> & {
    asChild?: boolean;
}): React$1.JSX.Element;
declare function BreadcrumbPage({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;
declare function BreadcrumbSeparator({ children, className, ...props }: React$1.ComponentProps<"li">): React$1.JSX.Element;
declare function BreadcrumbEllipsis({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;

declare function Calendar({ className, classNames, showOutsideDays, captionLayout, buttonVariant, locale, formatters, components, ...props }: React$1.ComponentProps<typeof DayPicker> & {
    buttonVariant?: React$1.ComponentProps<typeof Button>["variant"];
}): React$1.JSX.Element;
declare function CalendarDayButton({ className, day, modifiers, locale, ...props }: React$1.ComponentProps<typeof DayButton> & {
    locale?: Partial<Locale>;
}): React$1.JSX.Element;

declare function Card({ className, size, ...props }: React$1.ComponentProps<"div"> & {
    size?: "default" | "sm";
}): React$1.JSX.Element;
declare function CardHeader({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function CardTitle({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function CardDescription({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function CardAction({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function CardContent({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function CardFooter({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;

declare function Checkbox({ className, ...props }: React$1.ComponentProps<typeof Checkbox$1.Root>): React$1.JSX.Element;

declare function Collapsible({ ...props }: React.ComponentProps<typeof Collapsible$1.Root>): React$1.JSX.Element;
declare function CollapsibleTrigger({ ...props }: React.ComponentProps<typeof Collapsible$1.CollapsibleTrigger>): React$1.JSX.Element;
declare function CollapsibleContent({ ...props }: React.ComponentProps<typeof Collapsible$1.CollapsibleContent>): React$1.JSX.Element;

declare function Dialog({ ...props }: React$1.ComponentProps<typeof Dialog$1.Root>): React$1.JSX.Element;
declare function DialogTrigger({ ...props }: React$1.ComponentProps<typeof Dialog$1.Trigger>): React$1.JSX.Element;
declare function DialogPortal({ ...props }: React$1.ComponentProps<typeof Dialog$1.Portal>): React$1.JSX.Element;
declare function DialogClose({ ...props }: React$1.ComponentProps<typeof Dialog$1.Close>): React$1.JSX.Element;
declare function DialogOverlay({ className, ...props }: React$1.ComponentProps<typeof Dialog$1.Overlay>): React$1.JSX.Element;
declare function DialogContent({ className, children, showCloseButton, ...props }: React$1.ComponentProps<typeof Dialog$1.Content> & {
    showCloseButton?: boolean;
}): React$1.JSX.Element;
declare function DialogHeader({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function DialogFooter({ className, showCloseButton, children, ...props }: React$1.ComponentProps<"div"> & {
    showCloseButton?: boolean;
}): React$1.JSX.Element;
declare function DialogTitle({ className, ...props }: React$1.ComponentProps<typeof Dialog$1.Title>): React$1.JSX.Element;
declare function DialogDescription({ className, ...props }: React$1.ComponentProps<typeof Dialog$1.Description>): React$1.JSX.Element;

declare function Command({ className, ...props }: React$1.ComponentProps<typeof Command$1>): React$1.JSX.Element;
declare function CommandDialog({ title, description, children, className, showCloseButton, ...props }: React$1.ComponentProps<typeof Dialog> & {
    title?: string;
    description?: string;
    className?: string;
    showCloseButton?: boolean;
}): React$1.JSX.Element;
declare function CommandInput({ className, ...props }: React$1.ComponentProps<typeof Command$1.Input>): React$1.JSX.Element;
declare function CommandList({ className, ...props }: React$1.ComponentProps<typeof Command$1.List>): React$1.JSX.Element;
declare function CommandEmpty({ className, ...props }: React$1.ComponentProps<typeof Command$1.Empty>): React$1.JSX.Element;
declare function CommandGroup({ className, ...props }: React$1.ComponentProps<typeof Command$1.Group>): React$1.JSX.Element;
declare function CommandSeparator({ className, ...props }: React$1.ComponentProps<typeof Command$1.Separator>): React$1.JSX.Element;
declare function CommandItem({ className, children, ...props }: React$1.ComponentProps<typeof Command$1.Item>): React$1.JSX.Element;
declare function CommandShortcut({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;

type Api = {
    fire: (options?: Options) => void;
};
type ConfettiRef = Api | null;
type ConfettiProps = React__default.ComponentPropsWithoutRef<"canvas"> & {
    ref?: React__default.Ref<ConfettiRef>;
    options?: Options;
    globalOptions?: GlobalOptions;
    manualstart?: boolean;
    children?: ReactNode;
};
declare function Confetti({ ref, options, globalOptions, manualstart, children, ...props }: ConfettiProps): React__default.JSX.Element;
declare function ConfettiButton({ options, children, ...props }: React__default.ComponentProps<"button"> & {
    options?: Options & GlobalOptions & {
        canvas?: HTMLCanvasElement;
    };
}): React__default.JSX.Element;

declare function DropdownMenu({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Root>): React$1.JSX.Element;
declare function DropdownMenuPortal({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Portal>): React$1.JSX.Element;
declare function DropdownMenuTrigger({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Trigger>): React$1.JSX.Element;
declare function DropdownMenuContent({ className, align, sideOffset, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Content>): React$1.JSX.Element;
declare function DropdownMenuGroup({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Group>): React$1.JSX.Element;
declare function DropdownMenuItem({ className, inset, variant, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Item> & {
    inset?: boolean;
    variant?: "default" | "destructive";
}): React$1.JSX.Element;
declare function DropdownMenuCheckboxItem({ className, children, checked, inset, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.CheckboxItem> & {
    inset?: boolean;
}): React$1.JSX.Element;
declare function DropdownMenuRadioGroup({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.RadioGroup>): React$1.JSX.Element;
declare function DropdownMenuRadioItem({ className, children, inset, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.RadioItem> & {
    inset?: boolean;
}): React$1.JSX.Element;
declare function DropdownMenuLabel({ className, inset, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Label> & {
    inset?: boolean;
}): React$1.JSX.Element;
declare function DropdownMenuSeparator({ className, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Separator>): React$1.JSX.Element;
declare function DropdownMenuShortcut({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;
declare function DropdownMenuSub({ ...props }: React$1.ComponentProps<typeof DropdownMenu$1.Sub>): React$1.JSX.Element;
declare function DropdownMenuSubTrigger({ className, inset, children, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.SubTrigger> & {
    inset?: boolean;
}): React$1.JSX.Element;
declare function DropdownMenuSubContent({ className, ...props }: React$1.ComponentProps<typeof DropdownMenu$1.SubContent>): React$1.JSX.Element;

declare function EmptyState({ className, title, description, icon, actions, ...props }: React$1.ComponentProps<"div"> & {
    title: string;
    description?: string;
    icon?: React$1.ReactNode;
    actions?: React$1.ReactNode;
}): React$1.JSX.Element;

declare function HoverCard({ ...props }: React$1.ComponentProps<typeof HoverCard$1.Root>): React$1.JSX.Element;
declare function HoverCardTrigger({ ...props }: React$1.ComponentProps<typeof HoverCard$1.Trigger>): React$1.JSX.Element;
declare function HoverCardContent({ className, align, sideOffset, ...props }: React$1.ComponentProps<typeof HoverCard$1.Content>): React$1.JSX.Element;

declare function Input({ className, type, ...props }: React$1.ComponentProps<"input">): React$1.JSX.Element;

declare function InputGroup({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare const inputGroupAddonVariants: (props?: ({
    align?: "inline-end" | "inline-start" | "block-end" | "block-start" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function InputGroupAddon({ className, align, ...props }: React$1.ComponentProps<"div"> & VariantProps<typeof inputGroupAddonVariants>): React$1.JSX.Element;
declare const inputGroupButtonVariants: (props?: ({
    size?: "xs" | "sm" | "icon-xs" | "icon-sm" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function InputGroupButton({ className, type, variant, size, ...props }: Omit<React$1.ComponentProps<typeof Button>, "size"> & VariantProps<typeof inputGroupButtonVariants>): React$1.JSX.Element;
declare function InputGroupText({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;
declare function InputGroupInput({ className, ...props }: React$1.ComponentProps<"input">): React$1.JSX.Element;
declare function InputGroupTextarea({ className, ...props }: React$1.ComponentProps<"textarea">): React$1.JSX.Element;

declare function Kbd({ className, ...props }: React$1.ComponentProps<"kbd">): React$1.JSX.Element;
declare function KbdGroup({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;

declare function Label({ className, ...props }: React$1.ComponentProps<typeof Label$1.Root>): React$1.JSX.Element;

declare function Marquee({ className, reverse, pauseOnHover, children, vertical, repeat, ...props }: React$1.ComponentProps<"div"> & {
    reverse?: boolean;
    pauseOnHover?: boolean;
    vertical?: boolean;
    repeat?: number;
}): React$1.JSX.Element;

declare function NumberTicker({ value, startValue, direction, delay, className, decimalPlaces, ...props }: React$1.ComponentProps<"span"> & {
    value: number;
    startValue?: number;
    direction?: "up" | "down";
    delay?: number;
    decimalPlaces?: number;
}): React$1.JSX.Element;

declare function Pagination({ className, ...props }: React$1.ComponentProps<"nav">): React$1.JSX.Element;
declare function PaginationContent({ className, ...props }: React$1.ComponentProps<"ul">): React$1.JSX.Element;
declare function PaginationItem({ ...props }: React$1.ComponentProps<"li">): React$1.JSX.Element;
type PaginationLinkProps = {
    isActive?: boolean;
} & Pick<React$1.ComponentProps<typeof Button>, "size"> & React$1.ComponentProps<"a">;
declare function PaginationLink({ className, isActive, size, ...props }: PaginationLinkProps): React$1.JSX.Element;
declare function PaginationPrevious({ className, text, ...props }: React$1.ComponentProps<typeof PaginationLink> & {
    text?: string;
}): React$1.JSX.Element;
declare function PaginationNext({ className, text, ...props }: React$1.ComponentProps<typeof PaginationLink> & {
    text?: string;
}): React$1.JSX.Element;
declare function PaginationEllipsis({ className, ...props }: React$1.ComponentProps<"span">): React$1.JSX.Element;

declare function Popover({ ...props }: React$1.ComponentProps<typeof Popover$1.Root>): React$1.JSX.Element;
declare function PopoverTrigger({ ...props }: React$1.ComponentProps<typeof Popover$1.Trigger>): React$1.JSX.Element;
declare function PopoverContent({ className, align, sideOffset, ...props }: React$1.ComponentProps<typeof Popover$1.Content>): React$1.JSX.Element;
declare function PopoverAnchor({ ...props }: React$1.ComponentProps<typeof Popover$1.Anchor>): React$1.JSX.Element;
declare function PopoverHeader({ className, ...props }: React$1.ComponentProps<"div">): React$1.JSX.Element;
declare function PopoverTitle({ className, ...props }: React$1.ComponentProps<"h2">): React$1.JSX.Element;
declare function PopoverDescription({ className, ...props }: React$1.ComponentProps<"p">): React$1.JSX.Element;

declare function Progress({ className, value, ...props }: React$1.ComponentProps<typeof Progress$1.Root>): React$1.JSX.Element;

declare function RadioGroup({ className, ...props }: React$1.ComponentProps<typeof RadioGroup$1.Root>): React$1.JSX.Element;
declare function RadioGroupItem({ className, ...props }: React$1.ComponentProps<typeof RadioGroup$1.Item>): React$1.JSX.Element;

declare function SegmentedControl({ className, value, onChange, label, fill, children, ...props }: Omit<React$1.ComponentProps<"div">, "onChange"> & {
    value: string;
    onChange: (value: string) => void;
    label: string;
    fill?: boolean;
}): React$1.JSX.Element;
declare function SegmentedControlItem({ className, value: itemValue, disabled, children, ...props }: React$1.ComponentProps<"button"> & {
    value: string;
}): React$1.JSX.Element;

declare function Select({ ...props }: React$1.ComponentProps<typeof Select$1.Root>): React$1.JSX.Element;
declare function SelectGroup({ className, ...props }: React$1.ComponentProps<typeof Select$1.Group>): React$1.JSX.Element;
declare function SelectValue({ ...props }: React$1.ComponentProps<typeof Select$1.Value>): React$1.JSX.Element;
declare function SelectTrigger({ className, size, children, ...props }: React$1.ComponentProps<typeof Select$1.Trigger> & {
    size?: "sm" | "default";
}): React$1.JSX.Element;
declare function SelectContent({ className, children, position, align, ...props }: React$1.ComponentProps<typeof Select$1.Content>): React$1.JSX.Element;
declare function SelectLabel({ className, ...props }: React$1.ComponentProps<typeof Select$1.Label>): React$1.JSX.Element;
declare function SelectItem({ className, children, ...props }: React$1.ComponentProps<typeof Select$1.Item>): React$1.JSX.Element;
declare function SelectSeparator({ className, ...props }: React$1.ComponentProps<typeof Select$1.Separator>): React$1.JSX.Element;
declare function SelectScrollUpButton({ className, ...props }: React$1.ComponentProps<typeof Select$1.ScrollUpButton>): React$1.JSX.Element;
declare function SelectScrollDownButton({ className, ...props }: React$1.ComponentProps<typeof Select$1.ScrollDownButton>): React$1.JSX.Element;

declare function Separator({ className, orientation, decorative, ...props }: React$1.ComponentProps<typeof Separator$1.Root>): React$1.JSX.Element;

declare function ShimmerButton({ shimmerColor, shimmerSize, shimmerDuration, borderRadius, background, className, children, ...props }: React$1.ComponentProps<"button"> & {
    shimmerColor?: string;
    shimmerSize?: string;
    borderRadius?: string;
    shimmerDuration?: string;
    background?: string;
}): React$1.JSX.Element;

declare function Skeleton({ className, ...props }: React.ComponentProps<"div">): React$1.JSX.Element;

declare function Slider({ className, defaultValue, value, min, max, ...props }: React$1.ComponentProps<typeof Slider$1.Root>): React$1.JSX.Element;

declare const Toaster: ({ theme, ...props }: ToasterProps) => React$1.JSX.Element;

declare function Switch({ className, size, ...props }: React$1.ComponentProps<typeof Switch$1.Root> & {
    size?: "sm" | "default";
}): React$1.JSX.Element;

declare function Table({ className, ...props }: React$1.ComponentProps<"table">): React$1.JSX.Element;
declare function TableHeader({ className, ...props }: React$1.ComponentProps<"thead">): React$1.JSX.Element;
declare function TableBody({ className, ...props }: React$1.ComponentProps<"tbody">): React$1.JSX.Element;
declare function TableFooter({ className, ...props }: React$1.ComponentProps<"tfoot">): React$1.JSX.Element;
declare function TableRow({ className, ...props }: React$1.ComponentProps<"tr">): React$1.JSX.Element;
declare function TableHead({ className, ...props }: React$1.ComponentProps<"th">): React$1.JSX.Element;
declare function TableCell({ className, ...props }: React$1.ComponentProps<"td">): React$1.JSX.Element;
declare function TableCaption({ className, ...props }: React$1.ComponentProps<"caption">): React$1.JSX.Element;

declare function Tabs({ className, orientation, ...props }: React$1.ComponentProps<typeof Tabs$1.Root>): React$1.JSX.Element;
declare const tabsListVariants: (props?: ({
    variant?: "default" | "line" | null | undefined;
} & class_variance_authority_types.ClassProp) | undefined) => string;
declare function TabsList({ className, variant, ...props }: React$1.ComponentProps<typeof Tabs$1.List> & VariantProps<typeof tabsListVariants>): React$1.JSX.Element;
declare function TabsTrigger({ className, ...props }: React$1.ComponentProps<typeof Tabs$1.Trigger>): React$1.JSX.Element;
declare function TabsContent({ className, ...props }: React$1.ComponentProps<typeof Tabs$1.Content>): React$1.JSX.Element;

declare function Textarea({ className, ...props }: React$1.ComponentProps<"textarea">): React$1.JSX.Element;

declare function TooltipProvider({ delayDuration, ...props }: React$1.ComponentProps<typeof Tooltip$1.Provider>): React$1.JSX.Element;
declare function Tooltip({ ...props }: React$1.ComponentProps<typeof Tooltip$1.Root>): React$1.JSX.Element;
declare function TooltipTrigger({ ...props }: React$1.ComponentProps<typeof Tooltip$1.Trigger>): React$1.JSX.Element;
declare function TooltipContent({ className, sideOffset, children, ...props }: React$1.ComponentProps<typeof Tooltip$1.Content>): React$1.JSX.Element;

export { Alert, AlertAction, AlertDescription, AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogMedia, AlertDialogOverlay, AlertDialogPortal, AlertDialogTitle, AlertDialogTrigger, AlertTitle, AnimatedBeam, Avatar, AvatarBadge, AvatarFallback, AvatarGroup, AvatarGroupCount, AvatarImage, Badge, BentoCard, BentoGrid, BorderBeam, Breadcrumb, BreadcrumbEllipsis, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator, Button, Calendar, CalendarDayButton, Card, CardAction, CardContent, CardDescription, CardFooter, CardHeader, CardTitle, Checkbox, Collapsible, CollapsibleContent, CollapsibleTrigger, Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList, CommandSeparator, CommandShortcut, Confetti, ConfettiButton, type ConfettiRef, Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogOverlay, DialogPortal, DialogTitle, DialogTrigger, DropdownMenu, DropdownMenuCheckboxItem, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuLabel, DropdownMenuPortal, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuShortcut, DropdownMenuSub, DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger, EmptyState, HoverCard, HoverCardContent, HoverCardTrigger, Input, InputGroup, InputGroupAddon, InputGroupButton, InputGroupInput, InputGroupText, InputGroupTextarea, Kbd, KbdGroup, Label, Marquee, NumberTicker, Pagination, PaginationContent, PaginationEllipsis, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, Popover, PopoverAnchor, PopoverContent, PopoverDescription, PopoverHeader, PopoverTitle, PopoverTrigger, Progress, RadioGroup, RadioGroupItem, SegmentedControl, SegmentedControlItem, Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectScrollDownButton, SelectScrollUpButton, SelectSeparator, SelectTrigger, SelectValue, Separator, ShimmerButton, Skeleton, Slider, Switch, Table, TableBody, TableCaption, TableCell, TableFooter, TableHead, TableHeader, TableRow, Tabs, TabsContent, TabsList, TabsTrigger, Textarea, Toaster, Tooltip, TooltipContent, TooltipProvider, TooltipTrigger, badgeVariants, buttonVariants, cn, tabsListVariants };
